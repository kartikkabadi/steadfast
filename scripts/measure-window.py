import sys,json,subprocess,time
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
import importlib
m=importlib.import_module("measure-idle")
if m.snapshot()["app"]["pid"] is None:raise SystemExit("open the installed app before sampling")
read=lambda args:subprocess.check_output(args,text=True).strip()
r={"stage":sys.argv[1],"samples":[]}
for _ in range(5):
 r["samples"].append({"processes":m.snapshot(),"pressure":read(["sysctl","-n","kern.memorystatus_vm_pressure_level"]),"swap":read(["sysctl","-n","vm.swapusage"]),"vm":read(["vm_stat"])})
 time.sleep(.2)
Path(sys.argv[2]).write_text(json.dumps(r,indent=2)+"\n")
print(json.dumps({"stage":r["stage"],"app_footprint_MiB":[x["processes"]["app"]["usage"]["phys_footprint"]/1048576 for x in r["samples"]],"pressure":r["samples"][-1]["pressure"],"swap":r["samples"][-1]["swap"]},indent=2))
