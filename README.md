# SynoUPS-SController
A simple UPS control tool, (currently only) to add battery testing automation to supported Synology NAS's setup with APC Back UPS.

Synology DSM's UPS capability does not support periodically testing the UPS battery. APC Back UPS models do not have built-in self-testing, so this tool's focus is to do that. 

This script was validated against DSM7 OS with python2 and python3, however it should also with DSM6/python2. Its tested against an APC Back-UPS Pro 1000S, but should also work with all the other models that are supported by DSM UPS Manager (both USB and SNMP Master Mode)

## Howto:

### 1. SSH into the NAS
Activate SSHd under the synology control panel if you haven't done so and SSH into it. Note: under windows you might need a decent console with ssh (git bash?) or to use PuTTY.
```shell
ssh <username>@<nas_ip> -p <ssh_port>
```

### 2. Add a new user to upsd
Edit the upsd.users file and add a new user account after the existing account with permissions to run the testing commands
```shell
user@nas:/$ sudo vim /etc/ups/upsd.users
Password: <type your pwd>
```

Be careful with the VIM editor! In case you are not familiar with it:
* Move the cursor down <kbd>&#8595;</kbd> until you find the place where you want to add the new lines
* Press <kbd>I</kbd> to enter the INSERT MODE
* Edit the file as needed
* Press the <kbd>Esc</kbd> Key to leave the edit mode
* Press <kbd>:</kbd> to issue a command
* Write "wq" (write an quit) and hit <kbd>Enter</kbd>

So, edit the upsd.users file and add a new user with privileges to enable/disable the beeper (replace `<upsd_username>` and `<upsd_pwd>` with the desired values):
```shell
    [<upsd_username>]
        password = <upsd_pwd>
        actions = SET
        instcmds = ALL
```

### 3. Restart the upsd service
NOTE: This command no longer exists with latest DSM. 
```shell
synoservice --restart ups-usb
(wait a few seconds)
```

If the synoservice command doesn't exist, you can run
```shell
sudo upsd -c reload
```

### 4. Create or upload python and shell script
Clone the repo to a folder in your NAS or download the files and upload. 
Edit upscmd.py to set the user and pwd variables to the values created in Step 2.
Edit synoups-scontroller.sh to set the full path to the upscmd.py script. 

### 5. Make the scripts executable
```shell
sudo chmod u+x /volume<n>/path/to/upscmd.py
sudo chmod u+x /volume<n>/path/to/synoups-scontroller.sh
```

At this point you can test the scripts:
```shell
user@nas:/$ /volume<n>/path/to/synoups-scontroller.sh quick
```
The script accepts two strings for the argument, "quick" and "deep".  If nothing is called, "quick" is the default. 

There are some validation tests that are run to more quickly identfy errors, but I'm sure there are lots more to add later. 

### 6. Schedule it
Go to the DSM Web interface (Control panel -> Task scheduler) and add two tasks:
1. UPS Battery Quick Test
    - user: <ssh user with permissions to execute as setup in the previous steps>
    - shedule: Run on Fridays at 2am
    - command: `bash /volume<n>/path/to/synoups-scontroller.sh quick`
    - send email (your preference whether details should only be sent when the script ends abnormally)
2. UPS Battery Deep Test (similar to above)
    - schedule: Run on specific date and repeat every 6 months at 4am. 

This schedule should ensure that the two tests would never conflict. 

### 7. Run from DSM
Test full workflow by selecting the Quick Test and clicking Run. You should hear clicking and a beep from the UPS while its testing, and in a minute or two you should receive the email report. 

If the CLI testing worked but attempting to run from DSM interface doesn't work (either not hearing the testing, or receiving an email), you can troubleshoot by saving the script output results to an accessible location on the NAS, and reviewing the newest output.log. 

![dsm-task-logging example](https://d1nl0vjdid2hrd.cloudfront.net/syno-debug1.jpeg)


# Attribution

Thanks goes to keboose on [TrueNAS Forums](https://www.truenas.com/community/threads/is-there-a-better-way-to-poll-my-ups-for-self-test-status.75854/#post-532999) for inspiration and @renatopanda for creating a [similar tool](https://github.com/renatopanda/synology-nas-beeper) to control the audible beeping which I heavily sourced. 

    
# Ideas for future enhancements 
- Battery Level Notifier (using triggering?)
- Beeper controller
- Check for, and fix UPS bugs (upssched.conf missing cancel-timer waittimeup online, and UPSSafeShutdown not working)
