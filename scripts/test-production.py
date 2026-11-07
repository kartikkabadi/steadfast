import subprocess, socket, time, json, sys
from pathlib import Path
if sys.argv[1:] != ['--from-ui']:
 sys.exit('production verification requires --from-ui and a one-minute example.com block started in the app')
app='/Applications/Steadfast.app/Contents/MacOS/Steadfast'
checks=[]
def rpc(action,**kw):
 return subprocess.run([app,'--request-json',json.dumps(dict(action=action,**kw))],text=True,capture_output=True,timeout=75)
def check(ok,description):
 checks.append(dict(check=description,passed=bool(ok)))
 print(('pass: ' if ok else 'FAIL: ')+description,flush=True)
 if not ok: raise RuntimeError(description)
def addresses(name):
 try:return {x[4][0] for x in socket.getaddrinfo(name,443)}
 except socket.gaierror:return set()
def settles(predicate,timeout=5):
 # Cache invalidation is asynchronous in macOS, even after resolver files exist.
 deadline=time.monotonic()+timeout
 while True:
  if predicate():return True
  if time.monotonic()>=deadline:return False
  time.sleep(.1)
def curl():
 return subprocess.run(['curl','--noproxy','*','-sS','-I','--connect-timeout','3','--max-time','5','https://example.com'],capture_output=True,text=True)
def dig(tcp=False,record='A'):
 return subprocess.run(['dig','@127.0.0.1','-p','53535','www.example.com',record,'+time=1','+tries=1']+(['+tcp'] if tcp else []),capture_output=True,text=True,timeout=3)
report={'result':'failed','scope':'installed root service; production XPC; real system resolver, hosts and HTTPS; one-minute example.com commitment','checks':checks}
try:
 s=rpc('status');check(s.returncode==0,'installed signed app connects to production XPC')
 status=json.loads(s.stdout);check(status['sandbox']==False and not status.get('enforcementError'),'production service reports healthy, non-sandbox enforcement')
 before=Path('/etc/hosts').read_bytes();resolver=Path('/etc/resolver/example.com')
 check(not resolver.exists(),'test resolver does not exist before commitment')
 check(bool(addresses('example.com')) and curl().returncode==0,'example.com resolves and loads before blocking')
 print('baseline ready; waiting for one-minute example.com commitment from the installed UI...',flush=True)
 limit=time.monotonic()+120
 while time.monotonic()<limit:
  if resolver.exists(): break
  time.sleep(.4)
 else: raise RuntimeError('native UI one-minute commitment was not observed')
 observed=time.monotonic()
 print('observed the resolver; the production cli does not expose policy details',flush=True)
 s=rpc('status');check(s.returncode==0 and not json.loads(s.stdout).get('enforcementError'),'production enforcement succeeds')
 check(resolver.exists() and '53535' in resolver.read_text(),'real scoped resolver points at the local DNS service')
 check('0.0.0.0 example.com' in Path('/etc/hosts').read_text(),'real hosts file contains the managed block')
 check(settles(lambda: addresses('example.com') <= {'0.0.0.0','::','::ffff:0.0.0.0'}),'system resolver no longer returns public addresses')
 check(settles(lambda: not (addresses('www.example.com')-{'0.0.0.0','::','::ffff:0.0.0.0'})),'system resolver blocks the www subdomain')
 for tcp in [False,True]:
  for record in ['A','AAAA','HTTPS']:
   check('status: NXDOMAIN' in dig(tcp,record).stdout,f'local DNS blocks {record} over '+('TCP' if tcp else 'UDP'))
 check(curl().returncode!=0,'real HTTPS request fails while the commitment is active')
 uninstall=subprocess.run([app,'--can-uninstall'],text=True,capture_output=True,timeout=75)
 check(uninstall.returncode!=0,'production service refuses normal uninstall during the block')
 print('waiting for automatic expiry...',flush=True)
 while resolver.exists() and time.monotonic()<observed+70:time.sleep(.2)
 s=rpc('status');check(s.returncode==0,'production service remains reachable after expiry')
 check(not resolver.exists(),'scoped resolver is removed automatically at expiry')
 check(Path('/etc/hosts').read_bytes()==before,'original system hosts contents are restored exactly')
 check(settles(lambda: bool(addresses('example.com')-{'0.0.0.0','::','::ffff:0.0.0.0'}) and curl().returncode==0,timeout=15),
       'example.com resolves and loads again after expiry')
 report['seconds_since_block_observed']=round(time.monotonic()-observed,2)
 report['result']='passed'
finally:
 output = Path(__file__).resolve().parents[1] / 'outputs'
 output.mkdir(exist_ok=True)
 (output / 'production-verification.json').write_text(json.dumps(report,indent=2))
