#!/usr/bin/python
# upscmd emulator using NUT protocol with support for py2 and py3 requirements

# TODO: 
# Support outside APC Back Ups Pro
# -- Blocked by lack of devices

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

tn.write(b"USERNAME " + user.encode('utf-8') + b"\n")
print("USERNAME: " + tn.read_until(b"OK", timeout=2).decode('utf-8').strip())

tn.write(b"PASSWORD " + pwd.encode('utf-8') + b"\n")
print("PASSWORD: " + tn.read_until(b"OK", timeout=2).decode('utf-8').strip())

tn.write(b"INSTCMD ups " + cmd.encode('utf-8') + b"\n")
response = tn.read_until(b"OK", timeout=2).decode('utf-8')
print("INSTCMD ups " + cmd + ": " + response.strip())

if response.strip() != "OK":
  tn.write(b"LIST CMD ups\n")
  response = tn.read_until(b"END LIST CMD ups", timeout=2).decode('utf-8')
  print("\n>> AVAILABLE CMDS:")
  cmds = response.splitlines()[1:-1]
  for cmd in cmds:
    print(cmd.replace("CMD ups ", "- "))

tn.write(b"LOGOUT\n")
print(tn.read_all().decode('utf-8').rstrip("\n"))
