#!/bin/bash -e
# Wrapper Tool handling logic. Desiring a command as an argument or will default to quick test.

# Path to upscmd.py: looks next to this script first, then falls back to this default.
upscmdPyDefault="<path to upscmd.py e.g. /volume<n>/path/to/upscmd.py>"

scriptDir="$(dirname "$(readlink -f "$0")")"
upscmdPy="${scriptDir}/upscmd.py"
if [[ ! -f "${upscmdPy}" ]]; then
    upscmdPy="${upscmdPyDefault}"
fi
if [[ ! -f "${upscmdPy}" ]]; then
    echo "upscmd.py not found next to script or at ${upscmdPyDefault}, exiting..."
    exit 1
fi


upscBin="${UPSC_BIN:-/usr/bin/upsc}"
pollSeconds="${POLL_SECONDS:-5}"

# Deep test history (CSV) kept next to the script, used to compare runs over time.
historyFile="${HISTORY_FILE:-${scriptDir}/deep-test-history.csv}"

# Deep test analysis thresholds (see README "Reading the deep test report")
GOOD_RATIO=90     # actual discharge time >= 90% of what the UPS predicted -> GOOD
FAIR_RATIO=70     # >= 70% -> FAIR, below -> POOR
ACCEL_PCT=25      # second-half drain rate this much faster than first half -> warning
CAP_DROP_PCT=20   # estimated capacity this much lower than the previous run -> warning
MIN_USED_PCT=30   # less charge used than this -> result flagged as low confidence


#What type of test to run?

if [ $# -eq 0 ]; then
    testType="quick" # quick or deep
elif [[ $1 == "quick" || $1 == "deep" ]]; then
    testType=$1
else
    echo "Input incorrect, exiting..."
    exit 1
fi


# ---------------------------------------------------------------------------
# Helpers for deep test sampling and analysis
# ---------------------------------------------------------------------------

read_ups() {
    "${upscBin}" ups 2>/dev/null || true
}

# getvar <upsc output> <variable name>
getvar() {
    printf '%s\n' "$1" | awk -F': ' -v k="$2" '$1 == k { print $2; exit }'
}

# Appends one line to the sample file: epoch charge voltage load runtime status
record_sample() {
    local data
    data="$(read_ups)"
    local charge voltage load runtime status
    charge="$(getvar "${data}" battery.charge)"
    voltage="$(getvar "${data}" battery.voltage)"
    load="$(getvar "${data}" ups.load)"
    runtime="$(getvar "${data}" battery.runtime)"
    status="$(getvar "${data}" ups.status)"
    echo "$(date +%s) ${charge:-NA} ${voltage:-NA} ${load:-NA} ${runtime:-NA} ${status// /_}" >> "${sampleFile}"
}

print_progress() {
    tail -n 1 "${sampleFile}" | awk -v st="${startEpoch}" '{
        el = $1 - st
        printf "[%02d:%02d] charge %s%%  voltage %s V  load %s%%  runtime %s s  status %s\n",
               int(el / 60), el % 60, $2, $3, $4, $5, $6
    }'
}

# analyze_deep <final test result>
analyze_deep() {
    local result="$1"
    local prevDate="" prevCap=""

    if [[ -f "${historyFile}" ]] && [[ $(wc -l < "${historyFile}") -gt 1 ]]; then
        prevDate="$(tail -n 1 "${historyFile}" | cut -d, -f1)"
        prevCap="$(tail -n 1 "${historyFile}" | cut -d, -f8)"
    fi

    local report
    report="$(awk -v st="${startEpoch}" -v sc="${startCharge}" -v sr="${startRuntime}" \
        -v sv="${startVoltage}" -v nw="${nominalW}" -v res="${result}" \
        -v good="${GOOD_RATIO}" -v fair="${FAIR_RATIO}" -v accel="${ACCEL_PCT}" \
        -v capdrop="${CAP_DROP_PCT}" -v minused="${MIN_USED_PCT}" \
        -v prevdate="${prevDate}" -v prevcap="${prevCap}" -v now="$(date '+%Y-%m-%d %H:%M')" '
    $2 != "NA" { n++; t[n] = $1; c[n] = $2 + 0; v[n] = $3; l[n] = $4; rt[n] = $5 }
    END {
        if (n == 0) { print "No samples recorded, cannot analyze discharge."; exit }

        # End of discharge = lowest charge seen (charging resumes after the test)
        e = 1
        for (i = 1; i <= n; i++) if (c[i] < c[e]) e = i

        elapsed = (t[e] - st) / 60
        used = sc - c[e]
        if (elapsed <= 0 || used <= 0) { print "Battery charge did not drop, cannot analyze discharge."; exit }

        minv = (sv != "") ? sv + 0 : 999; lsum = 0; lcnt = 0
        for (i = 1; i <= e; i++) {
            if (v[i] != "NA" && v[i] + 0 < minv) minv = v[i] + 0
            if (l[i] != "NA") { lsum += l[i]; lcnt++ }
        }

        rate = used / elapsed
        extrap = elapsed * 100 / used
        # Compare actual discharge time with what the UPS predicted for the same
        # discharge: runtime estimate at start minus runtime estimate at the end.
        est = 0
        if (sr != "" && rt[e] != "NA" && sr + 0 > rt[e] + 0) est = (sr - rt[e]) / 60
        ratio = (est > 0) ? elapsed / est * 100 : 0

        # Split the discharge in half by time and compare drain rates
        midt = st + (t[e] - st) / 2; m = 1
        for (i = 1; i <= e; i++) if ((t[i] - midt)^2 < (t[m] - midt)^2) m = i
        h1 = (t[m] - st) / 60; h2 = (t[e] - t[m]) / 60
        r1 = (h1 > 0) ? (sc - c[m]) / h1 : 0
        r2 = (h2 > 0) ? (c[m] - c[e]) / h2 : 0
        accelpct = (r1 > 0) ? (r2 / r1 - 1) * 100 : 0

        avgload = (lcnt > 0) ? lsum / lcnt : 0
        watts = (nw != "" && lcnt > 0) ? avgload * nw / 100 : 0
        wh = watts * elapsed / 60
        cap = (used > 0) ? wh * 100 / used : 0

        if (est == 0) rating = "UNKNOWN"
        else if (ratio >= good) rating = "GOOD"
        else if (ratio >= fair) rating = "FAIR"
        else rating = "POOR"

        print "--- Deep Test Battery Report ---"
        printf "Test result:            %s\n", res
        printf "Discharge:              %d%% -> %d%% (%d%% used) in %.1f min\n", sc, c[e], used, elapsed
        if (watts > 0) printf "Average load:           %.0f%% (~%.0f W)\n", avgload, watts
        else           printf "Average load:           %.0f%%\n", avgload
        printf "Drain rate:             %.2f %%/min (first half %.2f, second half %.2f)\n", rate, r1, r2
        printf "Extrapolated runtime:   %.1f min at this load (100%% -> 0%%)\n", extrap
        if (est > 0) printf "UPS prediction:         %.1f min for this discharge (%.0f s -> %.0f s) -> actual is %.0f%% of prediction\n", est, sr, rt[e], ratio
        if (sv != "") printf "Battery voltage:        %.1f V at start, %.1f V minimum\n", sv, minv
        if (cap > 0) printf "Estimated capacity:     %.1f Wh usable (%.1f Wh delivered)\n", cap, wh
        printf "Battery rating:         %s\n", rating

        if (used < minused)
            printf "NOTE: only %d%% of charge used, estimates are low confidence.\n", used
        if (accelpct > accel)
            printf "WARNING: drain accelerated %.0f%% in the second half, a common sign of an aging battery.\n", accelpct
        if (prevcap + 0 > 0 && cap > 0) {
            chg = (cap / prevcap - 1) * 100
            printf "Since last deep test (%s): capacity %+.0f%% (%.1f -> %.1f Wh)\n", prevdate, chg, prevcap, cap
            if (chg <= -capdrop) printf "WARNING: capacity dropped more than %d%% since last test.\n", capdrop
        }

        printf "CSV,%s,%s,%d,%d,%.1f,%.0f,%.1f,%.1f,%.1f,%.1f,%.0f,%.2f,%.2f,%.1f,%s\n",
               now, res, sc, c[e], elapsed, watts, wh, cap, extrap, est, ratio, r1, r2, minv, rating
    }' "${sampleFile}")"

    echo -e "\n"
    printf '%s\n' "${report}" | grep -v '^CSV,' || true

    local csvLine
    csvLine="$(printf '%s\n' "${report}" | grep '^CSV,' | cut -d, -f2- || true)"
    if [[ -n "${csvLine}" ]]; then
        if [[ ! -f "${historyFile}" ]]; then
            echo "date,result,start_charge,end_charge,elapsed_min,avg_watts,delivered_wh,capacity_wh,extrapolated_min,ups_predicted_min,ratio_pct,rate_first_half,rate_second_half,min_voltage,rating" > "${historyFile}"
        fi
        echo "${csvLine}" >> "${historyFile}"
        echo "Result appended to ${historyFile}"
    fi
}


# Initial Capability Check - Exit script if fails
# Checking for compatibility - Unknown how many products support these testing commands, otherwise could use upsc for vendor/model validation

echo -e "\n"
echo "--- Starting Tool ${testType} pre-checks ---"

# Check that upsc can communicate with upsd.
if "${upscBin}" ups > /dev/null 2>&1; then
    echo "UPS client communicating"
else
    echo "UPS client failed, exiting..."
    exit 1
fi

# Check for commands to be used in upscmd.py, tool will exit due to -e flag.
# TODO: only check for input command instead.

python ${upscmdPy} chkCmds


# Deep test: take a starting snapshot for the discharge analysis

if [[ ${testType} == "deep" ]]; then
    sampleFile="$(mktemp)"
    trap 'rm -f "${sampleFile}"' EXIT

    startData="$(read_ups)"
    startEpoch="$(date +%s)"
    startCharge="$(getvar "${startData}" battery.charge)"
    startRuntime="$(getvar "${startData}" battery.runtime)"
    startVoltage="$(getvar "${startData}" battery.voltage)"
    nominalW="$(getvar "${startData}" ups.realpower.nominal)"

    if [[ -z "${startCharge}" ]]; then
        echo "Could not read battery.charge, exiting..."
        exit 1
    fi
    if (( ${startCharge%.*} < 95 )); then
        echo "WARNING: battery is at ${startCharge}%, not fully charged. The UPS may abort the test and the analysis will be less reliable."
    fi
    echo "Starting point: charge ${startCharge}%, runtime estimate ${startRuntime:-?} s, voltage ${startVoltage:-?} V"
fi


# Moving on - Lets get started

echo -e "\n"
echo "--- Starting Battery ${testType} test ---"
python ${upscmdPy} test.battery.start.${testType}

echo -e "\n"
echo "--- Now waiting for test results... ---"

#Set iterations to 20 for quick test and 1440 for deep test (at 5 second polling)
if [[ ${testType} == "quick" ]]; then
    j="20"
else
    j="1440"
fi

for (( i=0; i<$j; i++)); do
    sleep "${pollSeconds}"

    if [[ ${testType} == "deep" ]]; then
        record_sample
        if (( i % 12 == 11 )); then
            print_progress
        fi
    fi

    result="$("${upscBin}" ups ups.test.result 2>&1 | grep -v '^Init SSL' || true)"
    case "${result}" in
        "Done and passed")
            echo -e "\n"
            echo "--- UPS Test PASSED ---"
            if [[ ${testType} == "deep" ]]; then analyze_deep "${result}"; fi
            exit 0 ;;
        "No test initiated"|"In progress"|"Test scheduled"|"")
            continue ;;
        *)
            echo -e "\n"
            echo "--- UPS Test FAILED: ${result} ---"
            if [[ ${testType} == "deep" ]]; then analyze_deep "${result}"; fi
            exit 1 ;;
    esac
done

#If reached, operation failed
echo -e "\n"
echo "Operation timed out! UPS did not pass/fail in the allotted time frame"
if [[ ${testType} == "deep" ]]; then analyze_deep "Timed out"; fi
exit 1
