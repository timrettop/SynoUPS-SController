# SynoUPS-SController

A simple UPS control tool, (currently only) to add battery testing automation to supported Synology NAS's setup with APC Back UPS.

Synology DSM's UPS capability does not support periodically testing the UPS battery. APC Back UPS models do not have built-in self-testing, so this tool's focus is to do that.

This script was validated against DSM7 OS with python2 and python3, however it should also with DSM6/python2. Its tested against an APC Back-UPS Pro 1000S, but should also work with all the other models that are supported by DSM UPS Manager (both USB and SNMP Master Mode).

Some DSM updates have over-written the edited file in step 2, resulting in an errror in the script "ERR ACCESS-DENIED", however recent updates seem to leave it in place. After updates check the contents of upsd.users, correct and restart the upsd service following steps 2 and 3 if required.

## Howto

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

* Move the cursor down ↓ until you find the place where you want to add the new lines
* Press I to enter the INSERT MODE
* Edit the file as needed
* Press the Esc key to leave the edit mode
* Press : to issue a command
* Write "wq" (write an quit) and hit Enter

So, edit the upsd.users file and add a new user with privileges to enable/disable the beeper (replace `<upsd_username>` and `<upsd_pwd>` with the desired values):

```shell
    [<upsd_username>]
        password = <upsd_pwd>
        actions = SET
        instcmds = ALL
```

This can be done as a single line with here doc:
NOTE: shell history is currently stored in /var/tmp/.bash_history so logout/login and clean that file if needed.

```shell
sudo tee -a /etc/ups/upsd.users > /dev/null <<EOT
[<upsd_username>]
    password = <upsd_pwd>
    actions = SET
    instcmds = ALL
EOT
```

### 3. Restart the upsd service

```shell
sudo synosystemctl --restart ups-usb
(wait a few seconds)
```

NOTE: This command is no longer valid, kept as reference for older DSM versions.

```shell
synoservice --restart ups-usb
(wait a few seconds)
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

The script accepts two strings for the argument, "quick" and "deep". If nothing is called, "quick" is the default.

There are some validation tests that are run to more quickly identfy errors, but I'm sure there are lots more to add later.

### 6. Schedule it

Go to the DSM Web interface (Control panel -> Task scheduler) and add two tasks:

1. UPS Battery Quick Test
    * user: `ssh user` with permissions to execute as set up in the previous steps
    * shedule: Run on Fridays at 2am
    * command: `bash /volume<n>/path/to/synoups-scontroller.sh quick`
    * send email (your preference whether details should only be sent when the script ends abnormally)
2. UPS Battery Deep Test (see section below)
    * schedule: Recommend to set a reminder and run manually

This schedule should ensure that the two tests would never conflict.

### 7. Run from DSM

Test full workflow by selecting the Quick Test and clicking Run. You should hear clicking and a beep from the UPS while its testing, and in a minute or two you should receive the email report.

If the CLI testing worked but attempting to run from DSM interface doesn't work (either not hearing the testing, or receiving an email), you can troubleshoot by saving the script output results to an accessible location on the NAS, and reviewing the newest output.log.

![dsm-task-logging example](https://d1nl0vjdid2hrd.cloudfront.net/syno-debug1.jpeg)

## Running a deep test

A quick test only switches the UPS to battery for a few seconds. An aging lead-acid battery usually keeps passing it until it is nearly dead, so the quick test is a basic "does it switch over" check. The deep test is what actually measures battery health.

On APC units the deep test is a runtime calibration. The UPS runs the real load from the battery until the charge reaches about 25%, then switches back to mains and reports the result. The UPS firmware decides when the test ends; this script only starts it and waits for the outcome. A deep test usually takes 20 to 40 minutes depending on load and battery condition.

### Before you start

Run deep tests while you are around to watch, not unattended in the middle of the night. A deep test drains most of the battery, and several things can turn it into a real shutdown:

* **DSM's Standby timer.** If "Time before Synology NAS enters Standby Mode" is set to a fixed time, it starts counting when the UPS reports on battery (`OB`). Some APC Back-UPS models report `OL DISCHRG` (line power, discharging) during calibration, which does not start the timer. Check what your model reports in the first minute of the test.
* **Low battery.** If the UPS raises `LB` in `ups.status`, NUT treats it as critical and the NAS and every network UPS client will shut down. `LB` is driven by `battery.charge.low` and `battery.runtime.low`.
* **Network UPS clients.** Other machines using this NAS as their NUT server may have their own shutdown thresholds (for example, "shut down at 20% charge"). Make sure the test will end above the highest one.

Start from a full charge. The script warns you if the battery is below 95%, because the UPS may abort the test and the analysis is less reliable.

### Watching a test

From an SSH session on the NAS:

```shell
while true; do upsc ups 2>/dev/null | grep -E 'ups.status|battery.charge:|battery.runtime:|battery.voltage:|ups.test.result'; echo ---; sleep 30; done
```

The script also prints a progress line every minute during a deep test. Expect `ups.test.result` to read `In progress` and the charge to fall steadily. A brief "on battery" then "online" notification at the start is normal for models that report `OL DISCHRG`.

Stop the test early if `LB` appears, `battery.runtime` drops toward `battery.runtime.low`, the charge falls several points in a single reading, or the charge goes below about 25% and the test is still running:

```shell
python /volume<n>/path/to/upscmd.py test.battery.stop
```

When the test ends, `ups.status` returns to `OL CHRG`. Leave it on mains for a few hours to recharge before relying on full runtime.

### Reading the deep test report

At the end of a deep test (passed, failed, aborted, or timed out) the script prints a report built from samples taken every 5 seconds. A manually stopped test is still analyzed, so stopping at 30% still gives you useful numbers.

| Line | What it means |
| --- | --- |
| Discharge | Starting and lowest charge, and how long it took. |
| Average load | Mean `ups.load` during the test, converted to watts using `ups.realpower.nominal` when the UPS reports it. |
| Drain rate | Charge used per minute overall, and for the first and second halves of the test. |
| Extrapolated runtime | How long a full charge would last at this load, based on the measured drain. |
| UPS prediction | How long the UPS expected this discharge to take (`battery.runtime` at the start minus `battery.runtime` at the end), and the actual time as a percentage of that. This works whether the test runs to the UPS's own cutoff or you stop it early. |
| Battery voltage | Voltage at the start and the minimum under load. |
| Estimated capacity | Energy delivered during the test, scaled to a full charge. Use this to compare runs, not as a absolute value. |
| Battery rating | GOOD, FAIR or POOR, from the actual-vs-prediction percentage. |

The rating and warnings come from thresholds at the top of `synoups-scontroller.sh`:

* `GOOD_RATIO` (default 90) and `FAIR_RATIO` (default 70): actual discharge time as a percentage of the UPS's prediction.
* `ACCEL_PCT` (default 25): warns when the second half drains this much faster than the first. On APC units the first half normally drains *faster*, because the charge percentage is estimated from voltage and isn't linear. A battery that speeds up toward the end is losing capacity.
* `CAP_DROP_PCT` (default 20): warns when estimated capacity has fallen this much since the previous deep test.
* `MIN_USED_PCT` (default 30): if less charge than this was used, the estimates are flagged as low confidence.

The actual-vs-prediction figure compares the battery to the UPS's own model, and the UPS recalibrates that model after each deep test, so the next test will often land close to 100%. On some APC models the recalibrated `battery.runtime` counts down to the UPS's calibration cutoff (around 25%) rather than to empty, which is why the report compares predicted and actual time for the same discharge instead of using the extrapolated runtime. Over time, the estimated capacity trend is the more objective signal.

Example report (simulated run based on a real test of an APC Back-UPS RS 1000MS with a 5-year-old battery):

```text
--- Deep Test Battery Report ---
Test result:            Done and passed
Discharge:              100% -> 25% (75% used) in 22.0 min
Average load:           18% (~108 W)
Drain rate:             3.41 %/min (first half 4.27, second half 2.55)
Extrapolated runtime:   29.3 min at this load (100% -> 0%)
UPS prediction:         19.8 min for this discharge (1581 s -> 395 s) -> actual is 111% of prediction
Battery voltage:        25.5 V at start, 24.3 V minimum
Estimated capacity:     52.8 Wh usable (39.6 Wh delivered)
Battery rating:         GOOD
```

### History

Each deep test appends a line to `deep-test-history.csv` next to the script, and the next report compares its estimated capacity with the previous run. Keep the load similar between tests (same devices on the UPS) so the numbers are comparable. After replacing the battery, run a deep test once it has fully charged to record a new baseline.

### Scheduling

Keep the weekly quick test scheduled. For the deep test, either schedule it every 6 months at a time you are usually home, or set a calendar reminder and run it by hand:

```shell
bash /volume<n>/path/to/synoups-scontroller.sh deep
```

## Attribution

Thanks goes to keboose on [TrueNAS Forums](https://www.truenas.com/community/threads/is-there-a-better-way-to-poll-my-ups-for-self-test-status.75854/#post-532999) for inspiration and @renatopanda for creating a [similar tool](https://github.com/renatopanda/synology-nas-beeper) to control the audible beeping which I heavily sourced.

## Ideas for future enhancements

* Battery Level Notifier (using triggering?)
* Beeper controller
* Check for, and fix UPS bugs (upssched.conf missing cancel-timer waittimeup online, and UPSSafeShutdown not working)
