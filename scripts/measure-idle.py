#!/usr/bin/env python3
"""Sample installed app/helper resources. Pass an output JSON path and optional seconds (default 55)."""
import ctypes,json,subprocess,time,sys
from pathlib import Path
class Usage(ctypes.Structure):
 _fields_=[('uuid',ctypes.c_uint8*16)]+[(name,ctypes.c_uint64) for name in ['user_time','system_time','pkg_idle_wkups','interrupt_wkups','pageins','wired_size','resident_size','phys_footprint','proc_start_abstime','proc_exit_abstime','child_user_time','child_system_time','child_pkg_idle_wkups','child_interrupt_wkups','child_pageins','child_elapsed_abstime','diskio_bytesread','diskio_byteswritten','cpu_time_qos_default','cpu_time_qos_maintenance','cpu_time_qos_background','cpu_time_qos_utility','cpu_time_qos_legacy','cpu_time_qos_user_initiated','cpu_time_qos_user_interactive','billed_system_time','serviced_system_time','logical_writes','lifetime_max_phys_footprint','instructions','cycles','billed_energy','serviced_energy','interval_max_phys_footprint','runnable_time']]
lib=ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
def usage(pid):
 u=Usage()
 if lib.proc_pid_rusage(pid,4,ctypes.byref(u))!=0:return {'error':ctypes.get_errno()}
 return {k:getattr(u,k) for k in ['user_time','system_time','pkg_idle_wkups','interrupt_wkups','phys_footprint','resident_size','pageins','diskio_bytesread','diskio_byteswritten','logical_writes']}
PATTERNS={'app':'^/Applications/Steadfast.app/Contents/MacOS/Steadfast$','daemon':'^/Library/PrivilegedHelperTools/dev.local.steadfastd$'}
def snapshot():
 result={}
 for name,pattern in PATTERNS.items():
  found=subprocess.run(['pgrep','-f',pattern],text=True,capture_output=True)
  if found.returncode==1: result[name]={'pid':None,'usage':None};continue
  found.check_returncode()
  pids=found.stdout.split()
  if len(pids)!=1: raise RuntimeError(f'{name}: expected at most one process, found {pids}')
  pid=int(pids[0]);result[name]={'pid':pid,'usage':usage(pid)}
 return result

def job():
 result=subprocess.run(['launchctl','print','system/dev.local.steadfast.service'],text=True,capture_output=True)
 result.check_returncode()
 import re
 return {key:re.search(r'\b'+key+r' = ([^\n]+)',result.stdout)[1] for key in ['runs','last exit code','state']}

def main():
 a=snapshot();before=job();start=time.monotonic();print(json.dumps({'start':a,'job':before}),flush=True)
 time.sleep(float(sys.argv[2]) if len(sys.argv) > 2 else 55)
 b=snapshot();after=job();elapsed=time.monotonic()-start
 processes={}
 for name in PATTERNS:
  old,new=a[name],b[name]
  entry={'start':old,'end':new}
  if old['pid'] is None and new['pid'] is None:
   entry['absent_at_both_samples']=True
  elif old['pid']==new['pid'] and 'error' not in old['usage'] and 'error' not in new['usage']:
   delta={k:new['usage'][k]-old['usage'][k] for k in old['usage'] if k not in ['phys_footprint','resident_size']}
   entry['delta']=delta;entry['cpu_percent']=(delta['user_time']+delta['system_time'])/elapsed/1e7
  processes[name]=entry
 result={'seconds':elapsed,'job_start':before,'job_end':after,'processes':processes}
 Path(sys.argv[1]).write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)

if __name__ == "__main__":main()
