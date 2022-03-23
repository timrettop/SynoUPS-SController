#!/bin/bash -e 

upscmdPy="<path to upscmd.py e.g. /volume<n>/path/to/upscmd.py>"

if [ $# -eq 0 ]; then
	testType="quick" # quick or deep
elif [[ $1 == "quick" || $1 == "deep" ]]; then 
	testType=$1
else
	echo "Input incorrect, exiting..."
	exit 1
fi

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

