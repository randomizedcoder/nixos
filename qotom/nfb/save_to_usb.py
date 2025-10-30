# bootflash:save_to_usb.py  (Python 2.x, NX-OS)
import time
import cli  # NX-OS CLI API

ts = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
hn = cli.cli("show hostname").strip().split()[-1]
dst = "usb1:/configs/%s-%s.cfg" % (hn, ts)

cli.cli("terminal dont-ask")
cli.cli("copy running-config %s" % dst)
print("Wrote %s" % dst)
