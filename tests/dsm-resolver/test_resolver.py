#!/usr/bin/env python3
import copy,json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CAT=json.loads((ROOT/'config/dsm-targets.v1.json').read_text())
class Resolver(unittest.TestCase):
 def run_query(self, op='validate', model='SA6400', release='7.4.1-90080', module='custom-modules', method='PML', flags=None, known=True, catalog=None):
  req=dict(operation=op,model=model,release=release,mode=dict(module=module,method=method),cpu=dict(flags_known=known,flags=flags or []))
  with tempfile.TemporaryDirectory() as d:
   env=os.environ.copy()
   if catalog is not None:
    p=Path(d)/'catalog.json';p.write_text(json.dumps(catalog));env['MSHELL_DSM_CATALOG']=str(p)
   p=subprocess.run(['sh',str(ROOT/'tools/dsm-target-resolver.sh')],input=json.dumps(req),text=True,capture_output=True,env=env)
   out=json.loads(p.stdout);self.assertEqual(p.returncode,out['exit_code'],p.stderr)
   return out
 def test_current_cpu_modes(self):
  self.assertTrue(self.run_query()['ok'])
  self.assertFalse(self.run_query(module='all-modules',method='IML')['ok'])
  self.assertTrue(self.run_query(module='all-modules',method='IML',flags=['bmi2'])['ok'])
  self.assertFalse(self.run_query(module='anodrm-modules',method='IML')['ok'])
  self.assertFalse(self.run_query(module='all-modules',method='IML',known=False)['ok'])
 def test_unknown_and_cross_build(self):
  self.assertEqual(self.run_query(release='7.4.2-99999')['exit_code'],4)
  self.assertEqual(self.run_query(release='7.3.1-90080')['exit_code'],4)
  self.assertEqual(self.run_query(release='bad')['exit_code'],2)
  self.assertEqual(self.run_query(release='7.4.1-90080-1')['exit_code'],4)
  self.assertFalse(self.run_query(method='IML')['ok'])
 def test_legacy_kernel(self):
  self.assertEqual(self.run_query('identity',model='DS918+',release='7.2-64570')['target']['kernel'],'4.4.302')
  t=next(t for t in CAT['targets'] if t['platform']=='broadwell' and t['tuple'][0]==6)
  self.assertEqual(self.run_query('identity',model=t['model'],release=t['release'])['target']['kernel'],'3.10.105')
 def test_new_release_is_data_only(self):
  c=copy.deepcopy(CAT); t=copy.deepcopy(next(t for t in c['targets'] if t['model']=='SA6400' and t['release']=='7.4.1-90080-0' and t['channel']=='stable'))
  t.update(release='7.4.2-99999-0',version='7.4.2-99999',tuple=[7,4,2,99999,0],status='verified');c['targets'].append(t)
  self.assertTrue(self.run_query(release='7.4.2-99999',catalog=c)['ok'])
  t['status']='candidate';self.assertFalse(self.run_query(release='7.4.2-99999',catalog=c)['ok'])
  t['status']='verified';t['modes']=[];self.assertFalse(self.run_query(release='7.4.2-99999',catalog=c)['ok'])
 def test_numeric_sort(self):
  c=copy.deepcopy(CAT);base=next(t for t in c['targets'] if t['model']=='SA6400' and t['channel']=='stable')
  c['targets']=[]
  for minor,patch in [(4,2),(4,10),(10,0),(9,0)]:
   t=copy.deepcopy(base);t.update(release=f'7.{minor}.{patch}-99999-0',tuple=[7,minor,patch,99999,0]);c['targets'].append(t)
  out=self.run_query('list',flags=['bmi2'],catalog=c)
  self.assertEqual([t['target']['tuple'][1:3] for t in out['targets']],[[10,0],[9,0],[4,10],[4,2]])
 def test_schema_and_missing_recipe(self):
  c=copy.deepcopy(CAT);c['schema_version']=99;self.assertEqual(self.run_query(catalog=c)['exit_code'],3)
  c=copy.deepcopy(CAT);c['recipes']={};self.assertFalse(self.run_query(catalog=c)['ok'])
 def test_platform_policy_rejects_excluded_and_unregistered_kernel5(self):
  self.assertEqual(set(CAT['platform_policy']['kernel5_platforms']), {'epyc7002','epyc7003','icelaked','v1000nk','r1000nk','geminilakenk'})
  for platform in ('epyc7003ntb','unknown5'):
   c=copy.deepcopy(CAT);c['targets'][0]['platform']=platform;c['targets'][0]['kernel']='5.10.55'
   self.assertEqual(self.run_query(catalog=c)['exit_code'],3)
  c=copy.deepcopy(CAT);del c['platform_policy'];self.assertEqual(self.run_query(catalog=c)['exit_code'],3)
 def test_no_shell_whitelist(self):
  menu=(ROOT/'menu_m.sh').read_text()
  self.assertNotIn('CUSTOM_MODULES_MAX_DSM',menu)
  for name in ['functions.sh','functions_t.sh']:
   text=(ROOT/name).read_text(); block=text.split('function getvarsmshell()',1)[1].split('case ${MODEL}',1)[0]
   self.assertNotIn('90080',block);self.assertIn('mshellDsmResolve identity',block)
  self.assertEqual((ROOT/'functions.sh').read_text(),(ROOT/'functions_t.sh').read_text())
if __name__=='__main__': unittest.main()
