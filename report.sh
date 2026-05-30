#!/usr/bin/env bash

LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
START_TIME="$1"
END_TIME="$2"

if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] Log file not found: $LOG_FILE"
    exit 1
fi

awk -v start="$START_TIME" -v end="$END_TIME" '
function clean_value(v) {
    gsub("CPU:", "", v)
    gsub("MEM:", "", v)
    gsub("DISK_USED:", "", v)
    gsub("%", "", v)
    return v + 0
}

function update_stat(value, timestamp, name) {
    if (name == "cpu") {
        cpu_sum += value
        if (count == 1 || value > cpu_max) { cpu_max = value; cpu_max_time = timestamp }
        if (count == 1 || value < cpu_min) { cpu_min = value; cpu_min_time = timestamp }
    }

    if (name == "mem") {
        mem_sum += value
        if (count == 1 || value > mem_max) { mem_max = value; mem_max_time = timestamp }
        if (count == 1 || value < mem_min) { mem_min = value; mem_min_time = timestamp }
    }

    if (name == "disk") {
        disk_sum += value
        if (count == 1 || value > disk_max) { disk_max = value; disk_max_time = timestamp }
        if (count == 1 || value < disk_min) { disk_min = value; disk_min_time = timestamp }
    }
}

{
    date_part = $1
    time_part = $2

    gsub("\\[", "", date_part)
    gsub("\\]", "", time_part)

    timestamp = date_part " " time_part

    if (start != "" && timestamp < start) next
    if (end != "" && timestamp > end) next

    count++

    cpu = clean_value($4)
    mem = clean_value($5)
    disk = clean_value($6)

    update_stat(cpu, timestamp, "cpu")
    update_stat(mem, timestamp, "mem")
    update_stat(disk, timestamp, "disk")
}

END {
    print "====== STATISTICS REPORT ======"

    if (count == 0) {
        print "[WARNING] No data found."
        exit
    }

    print "[CPU]"
    printf "Average : %.1f%%\n", cpu_sum / count
    printf "Maximum : %.1f%% at %s\n", cpu_max, cpu_max_time
    printf "Minimum : %.1f%% at %s\n", cpu_min, cpu_min_time

    print "[Memory]"
    printf "Average : %.1f%%\n", mem_sum / count
    printf "Maximum : %.1f%% at %s\n", mem_max, mem_max_time
    printf "Minimum : %.1f%% at %s\n", mem_min, mem_min_time

    print "[Disk]"
    printf "Average : %.1f%%\n", disk_sum / count
    printf "Maximum : %.1f%% at %s\n", disk_max, disk_max_time
    printf "Minimum : %.1f%% at %s\n", disk_min, disk_min_time

    print "[Samples]"
    printf "Data Points: %d samples\n", count
}
' "$LOG_FILE"
