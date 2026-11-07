#!/usr/bin/env python3
"""Launch a disposable, unprivileged service. Never changes system DNS."""
from pathlib import Path
import subprocess, plistlib, os, json, time, hashlib, tempfile, shutil, re, socket, struct
root=Path(__file__).resolve().parent.parent
binpath=Path(subprocess.check_output(['swift','build','-c','release','--package-path',str(root),'--show-bin-path'],text=True).strip())
base=Path(tempfile.mkdtemp(prefix='steadfast-live-'))
label='dev.local.steadfast.test.'+str(os.getpid())
domain='gui/'+str(os.getuid())
plist=base/'service.plist'
state=base/'state'
log=base/'service.log'
for executable in ['Steadfast','steadfastd']:
 shutil.copy2(binpath/executable,base/executable)
plist.write_bytes(plistlib.dumps({'Label':label,'ProgramArguments':[str(base/'steadfastd'),'--sandbox',str(state),label],'MachServices':{label:True},'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},'ProcessType':'Adaptive','StandardErrorPath':str(log)}))
env={**os.environ,'STEADFAST_TEST_SERVICE':label}
before=hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest()
report=[]
def rpc(action,**kwargs):
 return subprocess.run([str(base/'Steadfast'),'--request-json',json.dumps({'action':action,**kwargs})],env=env,text=True,capture_output=True,timeout=8)
def check(value,description):
 if not value: raise AssertionError(description)
 report.append(description);print('pass: '+description,flush=True)
def dns(name,tcp=False,record='A'):
 args=['dig','@127.0.0.1','-p','55353',name,record,'+time=1','+tries=1']
 if tcp:args.append('+tcp')
 return subprocess.check_output(args,text=True,timeout=4)
def pid():
 result=subprocess.run(['launchctl','print',domain+'/'+label],text=True,capture_output=True)
 match=re.search(r'\bpid = ([0-9]+)',result.stdout)
 return int(match[1]) if match else None
def settles(condition,timeout=15):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  if condition(): return True
  time.sleep(.1)
 return False
observer=None
try:
 observer_source=root/'scripts/check-events.swift'
 observer_bin=base/'observe-events'
 subprocess.run(['swiftc','-parse-as-library','-I',str(binpath),str(observer_source),str(binpath/'SteadfastCore.o'),'-o',str(observer_bin)],check=True)
 subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True)
 for attempt in range(15):
  result=rpc('status')
  if result.returncode==0 and json.loads(result.stdout).get('enforcementError') is None:break
  time.sleep(.3)
 check(result.returncode==0,'native client connects to the live XPC service')
 check(json.loads(result.stdout).get('enforcementError') is None,'first cold reply waits for DNS listeners and enforcement')
 check(settles(lambda:pid() is None),'empty service exits cleanly and stays registered for on-demand launch')
 result=rpc('status')
 check(result.returncode==0 and json.loads(result.stdout).get('enforcementError') is None,'a status request relaunches the empty service on demand')
 check(pid() is not None,'on-demand request starts a new service process')
 event_log=base/'events.log'
 with event_log.open('w') as output:
  observer=subprocess.Popen([str(observer_bin),label],stdout=output,stderr=output)
 check(settles(lambda:event_log.exists() and 'observing' in event_log.read_text()),'native change observer subscribes before changes')
 result=rpc('commit',domains=['x.com','twitter.com'],minutes=1)
 check(result.returncode==0,'one-minute commitment accepted and persisted' + (': '+result.stderr.strip() if result.returncode else ''))
 check(settles(lambda:'active:1' in event_log.read_text()),'a commitment reaches the observer without polling')
 snapshot=json.loads(result.stdout); end=snapshot['policy']['commitments'][0]['endsAt']+978307200
 check('0.0.0.0 x.com' in (state/'hosts').read_text(),'managed hosts entries written in sandbox')
 check((state/'resolver'/'x.com').exists(),'scoped resolver created in sandbox')
 for tcp in [False,True]:
  for record in ['A','AAAA','HTTPS']:
   check('status: NXDOMAIN' in dns('api.x.com',tcp,record),f'{"TCP" if tcp else "UDP"} blocks {record} for subdomains')
 with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
  connection.settimeout(1)
  def datagram(identifier):
   packet=struct.pack('!HHHHHH',identifier,256,1,0,0,0)+b'\x03api\x01x\x03com\x00'+struct.pack('!HH',1,1)
   connection.sendto(packet,('127.0.0.1',55353));reply=connection.recv(4096)
   return reply[:2]==packet[:2] and reply[3]&15==3
  for identifier in range(24):
   check_result=datagram(identifier)
   if not check_result:raise AssertionError('UDP reply did not match its query')
   time.sleep(.15)
  check(True,'same UDP socket serves continuous queries for over three seconds')
  time.sleep(3.5)
  check(all(datagram(identifier) for identifier in range(24,30)),'same UDP socket resumes after a quiet interval with matching transaction IDs')
 with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
  connection.settimeout(.15)
  for invalid in [b'\x00\x01', b'\x00'*4097]:
   connection.sendto(invalid,('127.0.0.1',55353))
   try:connection.recv(4096);raise AssertionError('malformed or oversized UDP request received a reply')
   except TimeoutError:pass
  check(True,'malformed and oversized UDP datagrams are dropped')
  connection.settimeout(1)
  packet=struct.pack('!HHHHHH',1234,256,1,0,0,0)+b'\x01x\x03com\x00'+struct.pack('!HH',1,1)
  connection.sendto(packet,('127.0.0.1',55353));reply=connection.recv(4096)
  check(reply[:2]==packet[:2] and reply[3]&15==3,'valid UDP query succeeds on the same socket after invalid datagrams')
 with socket.create_connection(('127.0.0.1',55353),timeout=5) as connection:
  connection.settimeout(5)
  try:closed=connection.recv(1)==b''
  except ConnectionResetError:closed=True
  check(closed,'stalled TCP clients close within the existing timeout')
 collision=subprocess.run([str(base/'steadfastd'),'--sandbox',str(base/'collision'),label+'.collision'],capture_output=True,text=True,timeout=5)
 check(collision.returncode!=0,'an occupied DNS port fails startup instead of reporting healthy')
 check('status: SERVFAIL' in dns('example.com'),'unrelated domains are not falsely marked blocked')
 denied=rpc('delete',domains=['x.com'])
 check(denied.returncode!=0 and 'cannot be removed' in denied.stderr,'deletion request refused by the service')
 denied=rpc('commit',domains=['x.com'],minutes=1)
 check(denied.returncode!=0 and 'already blocked' in denied.stderr,'replacement of an active rule refused')
 denied=rpc('prepare-uninstall')
 check(denied.returncode!=0 and 'every commitment expires' in denied.stderr,'normal uninstall refused during a commitment')
 time.sleep(11)
 previous_pid=pid()
 check(previous_pid is not None,'active commitments keep the service resident past the idle grace period')
 subprocess.run(['launchctl','kill','SIGKILL',domain+'/'+label],check=True)
 check(settles(lambda:pid() is not None and pid()!=previous_pid),'launchd restarts a killed active service without a client request')
 for attempt in range(20):
  result=rpc('status')
  if result.returncode==0 and json.loads(result.stdout).get('enforcementError') is None:break
  time.sleep(.25)
 check(result.returncode==0 and len(json.loads(result.stdout)['policy']['commitments'])==1,'commitment survives killing and restarting the service')
 check('status: NXDOMAIN' in dns('twitter.com'),'DNS blocking survives the service restart')
 print('waiting for the actual one-minute deadline...',flush=True)
 while time.time()<end+2: time.sleep(min(1,end+2-time.time()))
 check(settles(lambda:'active:0' in event_log.read_text()),'expiry reaches the observer without polling')
 result=rpc('status');check(result.returncode==0,'service responds after the deadline')
 check(not (state/'resolver'/'x.com').exists(),'expired scoped resolver removed automatically')
 check((state/'hosts').read_text()=='127.0.0.1 localhost\n::1 localhost\n','original hosts restored automatically after expiry')
 check(rpc('prepare-uninstall').returncode==0,'normal uninstall allowed after all commitments expire')
 check(settles(lambda:pid() is None),'expired service releases its process again after cleanup')
 check(hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest()==before,'real system hosts configuration remains unchanged')
 print(json.dumps({'checks':len(report),'result':'passed','scope':'unprivileged sandbox; real localhost UDP/TCP DNS and XPC'},indent=2),flush=True)
except Exception:
 if log.exists():print(log.read_text())
 raise
finally:
 if observer is not None:
  observer.terminate(); observer.wait(timeout=5)
 subprocess.run(['launchctl','bootout',domain,str(plist)],capture_output=True)
 shutil.rmtree(base)
