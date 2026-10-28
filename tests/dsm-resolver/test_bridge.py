#!/usr/bin/env python3
"""Exercise integration adapters without sourcing MSHELL's device bootstrap."""
import hashlib,json,os,re,shutil,subprocess,tempfile,unittest,platform
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
BASH=shutil.which('bash')
def function(name,file='functions.sh'):
 s=(ROOT/file).read_text();a=re.search(r'^function '+name+r'\s*\(',s,re.M).start();m=re.search(r'^function ',s[a+1:],re.M)
 return s[a:a+1+m.start()] if m else s[a:]
def function_from(path,name):
 s=Path(path).read_text();a=re.search(r'^function '+name+r'\s*\(',s,re.M).start();m=re.search(r'^function ',s[a+1:],re.M)
 return s[a:a+1+m.start()] if m else s[a:]
class Bridge(unittest.TestCase):
 def test_identity_failure_clears_stale_globals(self):
  code=function('mshellLoadDsmResolver')+function('getvarsmshell')+'''
zeropadingver() { ZPADKVER="$1"; }
KVER=stale; ORIGIN_PLATFORM=stale
if getvarsmshell SA6400-7.4.2-99999; then exit 40; fi
[ -z "$KVER" ] && [ -z "$ORIGIN_PLATFORM" ] || exit 41
getvarsmshell SA6400-7.4.1-90080 || exit 42
[ "$KVER" = 5.10.55 ] && [ "$ORIGIN_PLATFORM" = epyc7002 ]
'''
  p=subprocess.run([BASH,'-c',code],env={**os.environ,'MSHELL_SCRIPT_ROOT':str(ROOT)},capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stderr)
 def test_remote_cpu_is_not_builder_cpu(self):
  code='. "$MSHELL_SCRIPT_ROOT/tools/dsm-resolver-bridge.sh"; mshellDsmResolve options SA6400 7.4.1-90080'
  p=subprocess.run([BASH,'-c',code],env={**os.environ,'MSHELL_SCRIPT_ROOT':str(ROOT),'MSHELL_DOCKER_BUILDER':'1'},capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stderr)
  x=json.loads(p.stdout)
  self.assertEqual([m['id'] for m in x['allowed_modes']],['custom-modules:PML'])
 def test_remote_cpu_uses_explicit_userconfig_snapshot(self):
  with tempfile.TemporaryDirectory() as d:
   cfg=Path(d)/'user_config.json'
   cfg.write_text(json.dumps({'general':{'target_cpu':{'flags_known':True,'flags':['bmi2'],'source':'target-snapshot'}}}))
   code='. "$MSHELL_SCRIPT_ROOT/tools/dsm-resolver-bridge.sh"; mshellDsmResolve options SA6400 7.4.1-90080'
   p=subprocess.run([BASH,'-c',code],env={**os.environ,'MSHELL_SCRIPT_ROOT':str(ROOT),'MSHELL_DOCKER_BUILDER':'1','MSHELL_USER_CONFIG':str(cfg)},capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stderr)
   x=json.loads(p.stdout)
   self.assertEqual([m['id'] for m in x['allowed_modes']],['all-modules:IML','all-modules:PML','custom-modules:PML','anodrm-modules:IML'])
 def test_friend_uses_resolver_kver_only_for_matching_model_platform_build(self):
  friend=Path(os.environ.get('TCRPFRIEND_SOURCE',ROOT.parent/'tcrpfriend'))/'buildroot/board/tcrpfriend/rootfs-overlay/root/boot.sh'
  if not friend.is_file() or 'resolver_kver_for_boot' not in friend.read_text(): self.skipTest('updated adjacent tcrpfriend checkout required')
  helper=function_from(friend,'resolver_kver_for_boot')
  with tempfile.TemporaryDirectory() as d:
   cfg=Path(d)/'user_config.json'
   code=helper+f'''\nresolver_kver_for_boot epyc7002 90080 "{cfg}"'''
   cfg.write_text(json.dumps({'general':{'resolver_platform':'epyc7002','version':'7.4.1-90080','kver':'5.10.55'}}))
   p=subprocess.run([BASH,'-c',code],capture_output=True,text=True)
   self.assertEqual((p.returncode,p.stdout.strip()),(0,'5.10.55'),p.stderr)
   for update in ({'resolver_platform':'r1000nk'},{'version':'7.4.1-99999'},{'kver':'5.10.55+evil'}):
    data={'resolver_platform':'epyc7002','version':'7.4.1-90080','kver':'5.10.55'}; data.update(update)
    cfg.write_text(json.dumps({'general':data}))
    p=subprocess.run([BASH,'-c',code],capture_output=True,text=True)
    self.assertNotEqual(p.returncode,0)
 def test_target_cpu_capture_intersects_all_processors(self):
  with tempfile.TemporaryDirectory() as d:
   cpuinfo=Path(d)/'cpuinfo'
   cpuinfo.write_text('processor : 0\nflags : fpu bmi2 avx\n\nprocessor : 1\nflags : fpu bmi2 sse\n')
   p=subprocess.run(['sh',str(ROOT/'tools/capture-target-cpu.sh')],env={**os.environ,'CPUINFO_FILE':str(cpuinfo)},capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stderr)
   self.assertEqual(json.loads(p.stdout),{'flags_known':True,'flags':['bmi2','fpu'],'source':'target-snapshot'})
 def test_recipe_local_index_with_ext_manager(self):
  if platform.system() != 'Linux': self.skipTest('ext-manager integration requires Linux GNU utilities')
  source=Path(os.environ.get('REDPILL_LOAD_SOURCE', str(ROOT.parent/'redpill-load')))
  if not source.exists(): self.skipTest('adjacent redpill-load required for integration test')
  with tempfile.TemporaryDirectory(prefix='mshell-resolver-') as d:
   d=Path(d);(d/'redpill-load/custom/extensions').mkdir(parents=True)
   shutil.copytree(source/'include',d/'redpill-load/include')
   shutil.copy(source/'ext-manager.sh',d/'redpill-load/ext-manager.sh')
   (d/'redpill-load/ext-manager.sh').chmod(0o755)
   (d/'redpill-load/bundled-exts.json').write_text('{"all-modules":"old","other":"preserve"}')
   payload=d/'payload';payload.write_text('local test payload\n')
   recipe={'mod_version':'v1','files':[{'name':'install.sh','url':payload.as_uri(),'sha256':hashlib.sha256(payload.read_bytes()).hexdigest(),'packed':False}],'scripts':{'on_boot':'install.sh'}}
   selection={'target':{'platform':'epyc7002','tuple':[7,4,1,90080,0],'kernel':'5.10.55'},'selected_mode':{'module':'custom-modules','recipe':recipe}}
   (d/'selection.json').write_text(json.dumps(selection))
   env={**os.environ,'MSHELL_SCRIPT_ROOT':str(d),'MODULE_USER_CONFIG':str(d/'user_config.json')}
   code=f'. "{ROOT}/tools/dsm-resolver-bridge.sh"; mshellDsmPinRecipe "$(cat "$MSHELL_SCRIPT_ROOT/selection.json")"'
   p=subprocess.run([BASH,'-c',code],env=env,capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stdout+p.stderr)
   p=subprocess.run([BASH,str(d/'redpill-load/ext-manager.sh'),'_update_platform_exts','epyc7002','74','51055','custom-modules'],env=env,capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stdout+p.stderr)
   self.assertEqual((d/'redpill-load/custom/extensions/custom-modules/epyc7002_74_51055/install.sh').read_bytes(),payload.read_bytes())
   bex=json.loads((d/'redpill-load/bundled-exts.json').read_text())
   self.assertEqual(bex['other'],'preserve');self.assertNotIn('all-modules',bex)
 def test_cancel_does_not_save(self):
  with tempfile.TemporaryDirectory() as d:
   code=function('selectversion','menu_m.sh')+'''
mshellLoadDsmResolver() { :; }
mshellDsmResolve() { echo '{"targets":[{"target":{"version":"7.4.1-90080"}}]}'; }
backtitle() { :; }; dlgmenuheight() { echo 1; }
dialog() { return 1; }
mshellSaveDsmSelection() { touch "$TMP_PATH/unexpected-save"; }
MODEL=SA6400
selectversion
[ ! -e "$TMP_PATH/unexpected-save" ]
'''
   p=subprocess.run([BASH,'-c',code],env={**os.environ,'TMP_PATH':d},capture_output=True,text=True)
   self.assertEqual(p.returncode,0,p.stderr)
if __name__=='__main__': unittest.main()
