#!/usr/bin/env python3
"""Compile an explicit support catalog; never infer approval for new releases.
Seed migration: --import-legacy reads committed adjacent repos. Subsequent builds
use --source with reviewed records, so future releases require data changes only.
"""
import argparse, hashlib, json, subprocess, re
from pathlib import Path
from functools import lru_cache

@lru_cache(maxsize=None)
def git_raw(root, path):
    try:
        return subprocess.check_output(['git','-C',str(root),'show',f'HEAD:{path}'],stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        return b'null'

@lru_cache(maxsize=None)
def git_json(root, path):
    return json.loads(git_raw(root,path))

def validate(data):
    assert data['schema_version'] == 1
    policy = data['platform_policy']
    if policy is not None:
        assert policy['version'] == 1
        supported = policy['kernel5_platforms']
        excluded = policy['excluded_platforms']
        dt = policy['dt_platforms']
        assert len(dt) == len(set(dt)) and set(dt) <= set(supported)
        assert all(isinstance(x, str) and x for x in supported + excluded)
        assert len(supported) == len(set(supported)) and len(excluded) == len(set(excluded))
        assert not set(supported) & set(excluded)
        assert 'epyc7003ntb' in excluded
        for target in data['targets']:
            assert target['platform'] not in excluded
            if target['kernel'].startswith('5.'):
                assert target['platform'] in supported, target['platform']
    seen = set()
    for t in data['targets']:
        key = (t['model'], t['release'], t['channel'])
        assert key not in seen, key
        seen.add(key)
        assert len(t['tuple']) == 5 and all(type(x) is int and x >= 0 for x in t['tuple'])
        assert t['release'] == '%d.%d.%d-%d-%d' % tuple(t['tuple'])
        assert t['kernel'] and t['platform'] and t['pat']['url']
        modes = set()
        for m in t['modes']:
            assert m['id'] not in modes
            modes.add(m['id'])
            assert m['id'] == m['module'] + ':' + m['method']
            assert isinstance(m['cpu_flags'], list)
            assert m['recipe']['files'] and re.fullmatch('[0-9a-f]{64}', m['recipe_sha256'])
            assert m['module'] in ('all-modules','custom-modules','anodrm-modules')
            assert m['method'] in ('IML','PML')
            assert all(isinstance(f, str) for f in m['cpu_flags'])
            for f in m['recipe']['files']:
                assert re.fullmatch('[0-9a-f]{64}', f['sha256'])
                assert f['name'] not in ('.','..') and '/' not in f['name']
                assert f['url'].startswith(('https://','http://'))
                assert type(f['packed']) is bool
    return data

p=argparse.ArgumentParser()
p.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1].parent/'redpill-load/config/catalog/dsm-targets.v1.json')
p.add_argument('--import-legacy', type=Path, help='parent containing related repositories')
p.add_argument('--output', type=Path, required=True)
a=p.parse_args()
if a.source:
    data=json.loads(a.source.read_text())
elif a.import_legacy:
    root=a.import_legacy
    models=json.loads((Path(__file__).resolve().parents[1]/'models.json').read_text())
    targets=[]
    recipes={}
    for channel,patfile in [('stable','pats.json'),('test','pats_t.json')]:
        pats=git_json(root/'redpill-load', 'config/'+patfile)
        for platform, info in models.items():
            for model in info['models']:
                for release, pat in pats.get(model,{}).items():
                    parts=release.split('-'); ver=[int(x) for x in parts[0].split('.')]
                    ver += [0]*(3-len(ver)); build=int(parts[1]); fix=int(parts[2]) if len(parts)>2 else 0
                    family='.'.join(map(str,ver[:2]))
                    kernel=info['productvers'].get(family)
                    if not kernel: continue
                    kernel=kernel.split('-')[-1]
                    if platform=='broadwell' and family=='6.2': kernel='3.10.105'
                    legacy_version='7.2' if build==64570 else '.'.join(map(str,ver))
                    config=f'config/{platform}/{".".join(map(str,ver))}-{build}/config.json'
                    if git_json(root/'redpill-load',config) is None: continue
                    modes=[]
                    for pack,methods in [('all-modules',['IML','PML']),('custom-modules',['PML']),('anodrm-modules',['IML'])]:
                        if pack=='custom-modules' and not kernel.startswith('5.'): continue
                        index=git_json(root/'tcrp-modules',pack+'/rpext-index.json')
                        url=index['releases'].get(f'{platform}_{ver[0]}{ver[1]}_{kernel.replace(".","")}')
                        if not url: continue
                        path=url.split('/main/')[-1]
                        try:
                            raw=git_raw(root/'tcrp-modules',path)
                            recipe=json.loads(raw)
                            if recipe is None: continue
                        except (subprocess.CalledProcessError, ValueError): continue
                        flags=['bmi2'] if kernel.startswith('5.') and ver[:2]>=[7,3] and pack!='custom-modules' else []
                        for method in methods:
                            modes.append(dict(id=pack+':'+method,module=pack,method=method,cpu_flags=flags,
                                recipe=recipe,recipe_sha256=hashlib.sha256(raw).hexdigest(),recipe_url=url))
                    targets.append(dict(model=model,platform=platform,release='%d.%d.%d-%d-%d'%tuple(ver+[build,fix]),
                        tuple=ver+[build,fix],channel=channel,status='inherited-supported',kernel=kernel,
                        legacy_version=legacy_version,version=f'{legacy_version}-{build}',config=config,pat=pat,modes=modes))
    sources={r:subprocess.check_output(['git','-C',str(root/r),'rev-parse','HEAD'],text=True).strip() for r in ['redpill-load','tcrp-modules']}
    data=dict(schema_version=1,sources=sources,targets=targets)
else: p.error('provide --source or --import-legacy')
# Accept compiled snapshots as input as well as expanded reviewed records.
for t in data['targets']:
    for m in t['modes']:
        if 'recipe' not in m:
            m['recipe'] = data['recipes'][m['recipe_sha256']]
validate(data)
recipes = {}
for t in data['targets']:
    for m in t['modes']:
        recipes[m['recipe_sha256']] = m.pop('recipe')
data['recipes'] = recipes
data.pop('catalog_id',None)
data['catalog_id']=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
# One target/recipe per line keeps catalog diffs reviewable and size bounded.
head={k:v for k,v in data.items() if k not in ('targets','recipes')}
text=json.dumps(head,ensure_ascii=False)[:-1]+',\n"targets":[\n'
text+=',\n'.join(json.dumps(t,ensure_ascii=False,separators=(',',':')) for t in data['targets'])
text+='\n],\n"recipes":{\n'
text+=',\n'.join(json.dumps(k)+':'+json.dumps(v,separators=(',',':')) for k,v in sorted(data['recipes'].items()))
a.output.write_text(text+'\n}}\n')
print(f'{len(data["targets"])} targets → {a.output}')
