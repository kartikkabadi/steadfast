#!/usr/bin/env python3
"""Exercise app blocking against a disposable, unprivileged service.

The sandboxed service only ever closes executables inside its own state folder,
so this test launches throwaway app bundles from there and never touches real apps.
"""
from pathlib import Path
import subprocess, plistlib, os, json, time, tempfile, shutil, re, signal
root=Path(__file__).resolve().parent.parent
binpath=Path(subprocess.check_output(['swift','build','-c','release','--package-path',str(root),'--show-bin-path'],text=True).strip())
base=Path(tempfile.mkdtemp(prefix='steadfast-apps-')).resolve()
label='dev.local.steadfast.test.apps.'+str(os.getpid())
domain='gui/'+str(os.getuid())
plist=base/'service.plist'
state=base/'state'
log=base/'service.log'
state.mkdir(mode=0o700)
for executable in ['Steadfast','steadfastd']:
 shutil.copy2(binpath/executable,base/executable)
plist.write_bytes(plistlib.dumps({'Label':label,'ProgramArguments':[str(base/'steadfastd'),'--sandbox',str(state),label],'MachServices':{label:True},'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},'ProcessType':'Adaptive','StandardErrorPath':str(log)}))
env={**os.environ,'STEADFAST_TEST_SERVICE':label}
hosts_before=None
APP_ID='com.example.steadfast-fake'
OTHER_ID='com.example.steadfast-other'
napper=base/'napper'
(base/'napper.c').write_text('#include <unistd.h>\nint main(void){ sleep(600); return 0; }\n')
subprocess.run(['clang','-O2',str(base/'napper.c'),'-o',str(napper)],check=True)
def bundle(folder,name,identifier):
 app=folder/f'{name}.app'
 (app/'Contents/MacOS').mkdir(parents=True)
 shutil.copy(napper,app/'Contents/MacOS'/name)
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleName':name,'CFBundleExecutable':name}))
 return app
apps=state/'Apps'; apps.mkdir()
fake=bundle(apps,'Fake',APP_ID)
helper=bundle(fake/'Contents/Frameworks','Fake Helper',APP_ID+'.helper')
other=bundle(apps,'Other',OTHER_ID)
outside=bundle(base,'Fake',APP_ID)  # same identifier, outside the sandbox scope
def executable(app,name=None): return str(app/'Contents/MacOS'/(name or app.stem))
def launch(app,name=None): return subprocess.Popen([executable(app,name)])
def rpc(action,**kwargs):
 return subprocess.run([str(base/'Steadfast'),'--request-json',json.dumps({'action':action,**kwargs})],env=env,text=True,capture_output=True,timeout=8)
def status(): return json.loads(rpc('status').stdout)
report=[]
def check(value,description):
 if not value: raise AssertionError(description)
 report.append(description);print('pass: '+description,flush=True)
def settles(condition,timeout=15,step=.02):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  if condition(): return True
  time.sleep(step)
 return False
def alive(process): return process.poll() is None
def until_dead(process,timeout):
 start=time.monotonic()
 return (time.monotonic()-start) if settles(lambda:not alive(process),timeout,.005) else None
processes=[]
try:
 subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True)
 check(settles(lambda:rpc('status').returncode==0,15,.3),'service starts in sandbox mode')
 hosts_before=(state/'hosts').read_text()

 early=launch(fake); processes.append(early)
 bystander=launch(other); processes.append(bystander)
 out_of_scope=launch(outside); processes.append(out_of_scope)
 time.sleep(.3)
 check(all(alive(p) for p in processes),'test apps start before the block')
 watcher=subprocess.Popen(['notifyutil','-1',label+'.apps'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); processes.append(watcher)
 time.sleep(.2)
 result=rpc('commit',apps=[{'bundleID':APP_ID,'name':'Fake'}],minutes=1)
 check(result.returncode==0,'an app-only block is accepted'+(': '+result.stderr.strip() if result.returncode else ''))
 snapshot=json.loads(result.stdout)
 closing=snapshot.get('appActivity',{}).get('closing',[])
 check(any(item['app']['bundleID']==APP_ID for item in closing),'an app open at the start of the block is given time to save')
 deadline=closing[0]['deadline']+978307200
 check(9 <= deadline-time.time() <= 11,'the save window lasts about ten seconds')
 check(settles(lambda:watcher.poll() is not None,5),'the menu bar app is notified that an app must close')
 check((state/'hosts').read_text()==hosts_before,'an app-only block leaves DNS configuration unchanged')
 time.sleep(4)
 check(alive(early),'the open app keeps running during its save window')
 elapsed=until_dead(early,10)
 check(elapsed is not None,'the open app is closed once its save window ends')
 recent=status()['appActivity']['recent']
 check(any(item['app']['bundleID']==APP_ID for item in recent),'the forced close is recorded for the blocked-app notice')

 latencies=[]
 for attempt in range(5):
  process=launch(fake); processes.append(process)
  elapsed=until_dead(process,3)
  check(elapsed is not None,f'relaunch {attempt+1} during the block is stopped')
  latencies.append(elapsed)
 print('relaunch stop times (ms): '+', '.join(f'{value*1000:.0f}' for value in latencies),flush=True)
 check(max(latencies) < .05,'relaunches are stopped within 50 ms')
 nested=launch(helper); processes.append(nested)
 check(until_dead(nested,3) is not None,'a helper inside the blocked app is stopped too')
 renamed=apps/'Renamed.app'; shutil.copytree(fake,renamed)
 copy=launch(renamed,'Fake'); processes.append(copy)
 check(until_dead(copy,3) is not None,'a renamed copy of the app is still recognized by its bundle identifier')
 trap=apps/'Trap.app'; (trap/'Contents/MacOS').mkdir(parents=True); shutil.copy(napper,trap/'Contents/MacOS/Trap')
 os.mkfifo(trap/'Contents/Info.plist')
 trapped=launch(trap); processes.append(trapped)
 time.sleep(1.5)
 check(rpc('status').returncode==0,'a pipe planted as Info.plist cannot stall the service')
 again=launch(fake); processes.append(again)
 check(until_dead(again,3) is not None,'blocking keeps working after reading a planted pipe')
 (fake/'Contents/Resources/bin').mkdir(parents=True); shutil.copy(napper,fake/'Contents/Resources/bin/tool')
 tool=subprocess.Popen([str(fake/'Contents/Resources/bin/tool')]); processes.append(tool)
 time.sleep(1.5)
 check(alive(tool),'a command-line tool inside the blocked app keeps running')
 storm=subprocess.Popen(['/bin/sh','-c','i=0; while [ $i -lt 1000 ]; do /usr/bin/true & i=$((i+1)); done; wait'])
 processes.append(storm)
 time.sleep(.2)
 during=launch(fake); processes.append(during)
 elapsed=until_dead(during,3)
 check(elapsed is not None and elapsed < .5,f'a launch during a burst of 1,000 processes is still stopped quickly ({(elapsed or 0)*1000:.0f} ms)')
 started=time.monotonic(); reply=rpc('status'); latency=time.monotonic()-started
 check(reply.returncode==0 and latency < 2,f'the service stays responsive during the burst ({latency*1000:.0f} ms)')
 storm.wait(timeout=60)
 check(alive(bystander),'an unblocked app keeps running')
 check(alive(out_of_scope),'the sandboxed service never closes processes outside its test folder')
 check(rpc('commit',apps=[{'bundleID':'com.apple.finder','name':'Finder'}],minutes=1).returncode!=0,'protected system apps are refused')
 check(rpc('commit',apps=[{'bundleID':APP_ID.upper(),'name':'Fake'}],minutes=1).returncode!=0,'an app that is already blocked cannot be blocked twice')

 end=snapshot['policy']['commitments'][0]['endsAt']+978307200
 time.sleep(max(0,end-time.time())+1.5)
 after=launch(fake); processes.append(after)
 time.sleep(1.5)
 check(alive(after),'the app opens normally after the block ends')
 check(settles(lambda:not status()['appActivity']['closing'],5),'nothing is waiting to close after the block ends')
 print(f'all {len(report)} app blocking checks passed',flush=True)
finally:
 for process in processes:
  if alive(process): process.send_signal(signal.SIGKILL)
 subprocess.run(['launchctl','bootout',domain+'/'+label],capture_output=True)
 if log.exists() and log.read_text().strip(): print('service log:\n'+log.read_text()[-4000:])
 shutil.rmtree(base,ignore_errors=True)
