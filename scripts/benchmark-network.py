#!/usr/bin/env python3
"""Measure the real service in a disposable, unprivileged localhost sandbox."""
from pathlib import Path
import itertools,json,os,plistlib,re,shutil,socket,statistics,struct,subprocess,sys,tempfile,time
root=Path(__file__).resolve().parents[1]
if len(sys.argv)!=2:raise SystemExit('usage: python3 scripts/benchmark-network.py output.json (build release first)')
output=Path(sys.argv[1])
binaries=Path(subprocess.check_output(['swift','build','--package-path',str(root),'-c','release','--show-bin-path'],text=True).strip())
helper=binaries/'steadfastd'
label='dev.local.steadfast.test.speed.'+str(os.getpid());domain='gui/'+str(os.getuid())
ids=itertools.count(1)
ports=[]
packet=struct.pack('!HHHHHH',42,256,1,0,0,0)+b'\x03api\x07site499\x07example\x00'+struct.pack('!HH',1,1)
with tempfile.TemporaryDirectory(prefix='steadfast-speed-') as folder:
 base=Path(folder)
 shutil.copy2(helper,base/'steadfastd')
 subprocess.run(['swiftc','-O','-parse-as-library','-I',str(binaries),str(root/'scripts/benchmark-service.swift'),str(binaries/'SteadfastCore.o'),'-o',str(base/'probe')],check=True)
 job={'Label':label,'ProgramArguments':[str(base/'steadfastd'),'--sandbox',str(base/'state'),label],'MachServices':{label:True},'RunAtLoad':True,'KeepAlive':{'SuccessfulExit':False},'ProcessType':'Adaptive','StandardErrorPath':str(base/'error.log')}
 plist=base/'service.plist';plist.write_bytes(plistlib.dumps(job))
 try:
  subprocess.run(['launchctl','bootstrap',domain,str(plist)],check=True)
  result=subprocess.run([str(base/'probe'),label],capture_output=True,text=True,timeout=75)
  assert result.returncode==0,result.stderr
  report=json.loads(result.stdout)
  def query(connection):
   wire=struct.pack('!H',next(ids))+packet[2:]
   start=time.perf_counter_ns();connection.sendto(wire,('127.0.0.1',55353));ports.append(connection.getsockname()[1]);reply=connection.recv(4096)
   assert reply[:2]==wire[:2] and reply[3]&15==3
   return (time.perf_counter_ns()-start)/1e6
  fresh=[];fresh_timeouts=0
  for _ in range(3):
   times=[]
   for _ in range(200):
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as connection:
     connection.settimeout(.2)
     try:times.append(query(connection))
     except TimeoutError:fresh_timeouts+=1
   fresh.append(times)
  persistent=[];failures=0
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as connection:
   connection.settimeout(.2)
   for _ in range(20):
    try:persistent.append(query(connection))
    except TimeoutError:failures+=1
  report.update({'fresh_udp_ms':fresh,'fresh_udp_timeouts':fresh_timeouts,'fresh_query_count':600,'unique_source_ports':len(set(ports)),'same_socket_udp_ms':persistent,'same_socket_timeouts':failures,'scope':'unprivileged live service, 500-site commit and actual localhost UDP; temporary executable/state paths'})
  output.write_text(json.dumps(report,indent=2)+'\n')
  print(json.dumps({key:value if key not in ['warm_status_500_ms','fresh_udp_ms','same_socket_udp_ms'] else statistics.median(value) if key!='fresh_udp_ms' else [statistics.median(x) for x in value] for key,value in report.items()}),flush=True)
 finally:
  subprocess.run(['launchctl','bootout',domain+'/'+label],capture_output=True)
