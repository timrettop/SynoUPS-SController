#!/usr/bin/python2
# Author: Tim Potter 
# upscmd emulator using NUT protocol  

# TODO: 
# Update to support py3 
# DSM6 Support validation 
# Maybe - Support outside APC Back Ups Pro

# NUT protocol for reference: https://networkupstools.org/docs/developer-guide.chunked/ar01s09.html

import sys
import telnetlib

user = "<upsd user>"
pwd = "<upsd user password>"

if len(sys.argv) == 2:
    cmd = sys.argv[1]
else:
    print("the ups command to issue is missing.")
    print("example: upscmd.py test.battery.start.quick")
    exit(1)

tn = telnetlib.Telnet("127.0.0.1", 3493)

tn.write("USERNAME {0}\n".format(user))
response = tn.read_until("OK", timeout=2)
print("USERNAME: {0}".format(response.strip()))

tn.write("PASSWORD {0}\n".format(pwd))
response = tn.read_until("OK", timeout=2)
print("PASSWORD: {0}".format(response.strip()))

tn.write("INSTCMD ups {0}\n".format(cmd))
response = tn.read_until("OK", timeout=2)
print("INSTCMD ups {0}: {1}".format(cmd, response.strip()))

if response.strip() != "OK":
  tn.write("LIST CMD ups\n")
  response = tn.read_until("END LIST CMD ups", timeout=2)
  print("\n>> AVAILABLE CMDS:")
  cmds = response.splitlines()[1:-1]
  for cmd in cmds:
    print(cmd.replace("CMD ups ", "- "))

tn.write("LOGOUT\n")
print tn.read_all().rstrip("\n")
