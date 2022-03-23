#!/bin/bash -e
# Wrapper Tool handling logic. Desiring a command as an argument or will default to quick test.

upscmdPy="<path to upscmd.py e.g. /volume<n>/path/to/upscmd.py>"


#What type of test to run?

if [ $# -eq 0 ]; then
    testType="quick" # quick or deep
elif [[ $1 == "quick" || $1 == "deep" ]]; then
    testType=$1
else
    echo "Input incorrect, exiting..."
    exit 1
fi

# Initial Capability Check - Exit script if fails
# Checking for compatibility - Unknown how many products support these testing commands, otherwise could use upsc for vendor/model validation

# Check that upsc can communicate with upsd. If command fails to make a connection, tool will exit due to -e flag

upsc ups > /dev/null 2>&1 && echo "UPS client communicating" || echo "UPS client failed, exiting..."

# Check for commands to be used in upscmd.py, tool will exit due to -e flag.
# TODO: only check for input command instead.

python ${upscmdPy} chkCmds

# Moving on - Lets get started

echo "Starting -- $(date)"
echo "Starting ${testType} test"
python ${upscmdPy} test.battery.start.${testType}
echo "Waiting for test results..."

#Set iterations to 20 for quick test and 1440 for deep test
if [[ ${testType} == "quick" ]]; then
    j="20"
else
    j="1440"
fi

for (( i=0; i<$j; i++)); do
    sleep 5
    result="$(/usr/bin/upsc ups ups.test.result 2>&1 | grep -v '^Init SSL')"
    if [[ ${result} == "Done and passed" ]]; then
        echo "UPS Test Passed"
        echo "Ended -- $(date)"
        exit 0
    elif [[ ${result} != "No test initiated" ]]; then
        echo "--- UPS Test FAILED ---"
        echo "Ended -- $(date)"
        exit 1
    fi
done

#If reached, operation failed
echo "Operation timed out! UPS did not pass/fail in the allotted time frame"
echo "Ended -- $(date)"
exit 1
