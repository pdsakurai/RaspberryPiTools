#!/bin/bash

readonly directory_root="/mnt/eHDD/Software/Devices/Raspberry Pi 3 B+"
readonly directory_snapshot="$directory_root/Snapshots"
readonly script_backup="$directory_root/bkup_rpimage/bkup_rpimage.sh"
readonly script_shrink="$directory_root/PiShrink/pishrink.sh"
readonly fullfilepath_backup="$directory_root/rpi_backup.img"
readonly fullfilepath_log="$directory_root/log.txt"

readonly debug_mode=
readonly forced_shrink=

function log() {
    local -r tag="backup_rpi.sh[$$]"
    local text="$( [[ -n "$debug_mode" ]] && printf "!DEBUG MODE! " )${@:?Cannot do empty logging}"
    local -r time_now="$( date "+%Y-%m-%dT%H:%M:%S.%3N" )"
    logger -t "$tag" "$text"

    text="<$time_now> $tag: $text\n"
    [[ -e "$fullfilepath_log" ]] \
        && sed -i "1 s|^|$text|" "$fullfilepath_log" \
        || printf "$text" > "$fullfilepath_log"
}

function print_elapsed_time() {
    local display_seconds=$SECONDS

    local -r seconds_in_one_hour=3600
    local -r display_hours=$(( display_seconds / seconds_in_one_hour ))
    display_seconds=$(( display_seconds % seconds_in_one_hour ))

    local -r seconds_in_one_minute=60
    local -r display_minutes=$(( display_seconds / seconds_in_one_minute ))
    display_seconds=$(( display_seconds % seconds_in_one_minute ))

    printf "%02d:%02d:%02d" $display_hours $display_minutes $display_seconds
}

function absolute() {
    local number=${1:?Missing: Number}

    [[ $number -lt 0 ]] && number=$(( number * -1 ))

    printf "$number"
}

function get_delta() {
    local -r numerator=${1:?Missing: Numerator}
    local -r denominator=${2:?Missing: Denominator}
    
    local -r precision=9
    local -r precision_multiplier=$(( 10**precision ))
    local result=$(( (numerator*precision_multiplier/denominator) - precision_multiplier ))

    [[ $result -lt 0 ]] && local -r sign=- || local -r sign=+
    result=$( absolute "$result" )

    local -r whole_number_multiplier=$(( 10**(precision - 2) ))
    local -r whole_number=$(( result/whole_number_multiplier ))

    local -r fraction_number_multiplier=$(( 10**(precision - 4) ))
    local -r fraction_number=$(( (result%(whole_number*whole_number_multiplier))/fraction_number_multiplier ))

    printf "%s%d.%02d" $sign $whole_number $fraction_number
}

function byte_to_gigabyte() {
    local -r bytes=${1:?Missing: Bytes}

    local -r bytes_in_one_gigabyte=$(( 10**9 ))
    local -r precision=$(( bytes_in_one_gigabyte / 10**2 ))

    local -r whole_number=$(( bytes / bytes_in_one_gigabyte ))
    local -r fractional_number=$(( (bytes%(whole_number*bytes_in_one_gigabyte)) / precision ))

    printf "%d.%02d" $whole_number $fractional_number
}

function create_daily_backup() {
    SECONDS=0
    [[ -z $debug_mode ]] && sudo bash "$script_backup" start -c "$fullfilepath_backup"
    local -r elapsed_time="$( print_elapsed_time )"

    if [[ ! -f "$fullfilepath_backup" ]]; then
        log "Failed to create a backup @ \"${fullfilepath_backup}\"."
        exit 1
    fi
    local file_size="$( stat -c%s "$fullfilepath_backup" )"
    file_size="$( byte_to_gigabyte "$file_size" )"

    log "Completed the ${file_size}GB backup within $elapsed_time @ \"${fullfilepath_backup}\"."
}

function create_snapshot() {
    local snapshot_filename="${fullfilepath_backup%.*}_$(date +%Y-%m-%d).img"
    local snapshot_fullfilepath="$directory_snapshot/${snapshot_filename##*/}"

    if [[ $(date +%d) == "01" || $(date +%d) == "16" || -n "$forced_shrink" ]] \
        && [[ $( ls -1A "$directory_snapshot" | grep -c "$snapshot_filename" 2> /dev/null ) -eq 0 ]]; then
        SECONDS=0
        [[ -z $debug_mode ]] && sudo bash "$script_shrink" -Z "$fullfilepath_backup" "$snapshot_fullfilepath"
        local -r elapsed_time="$( print_elapsed_time )"

        snapshot_filename="$( ls -1A "$directory_snapshot" | grep "$snapshot_filename" 2> /dev/null )"
        snapshot_fullfilepath="$directory_snapshot/$snapshot_filename"
        if [[ -z "$snapshot_filename" || ! -f "$snapshot_fullfilepath" ]]; then
            log "Failed to create a snapshot @ \"${snapshot_fullfilepath}\" based on \"${fullfilepath_backup}\"."
            exit 1
        fi
    
        local filesize="$( stat -c%s "$snapshot_fullfilepath" )"
        local delta="$( stat -c%s "$fullfilepath_backup" )"
        delta="$( get_delta "$filesize" "$delta" )"
        filesize="$( byte_to_gigabyte "$filesize" )"

        log "Created the snapshot and shrank it by ${delta}% to ${filesize}GB within ${elapsed_time} @ \"${snapshot_fullfilepath}\"."
    fi
}

function truncate_snapshots() {
    local -r snapshots_count="$( ls -1A "$directory_snapshot" | grep -c "rpi_backup_" )"
    local -r max_snapshots_count="12"

    if [[ $snapshots_count -gt $max_snapshots_count ]]; then
        local -r snapshots_to_delete_count="$(( snapshots_count - max_snapshots_count ))"

        ls -1AX "$directory_snapshot" | head -$snapshots_to_delete_count | while read item; do
            local old_snapshot="$directory_snapshot/$item"
            [[ -z $debug_mode ]] && rm "$old_snapshot"
            log "Removed old snapshot: \"$old_snapshot\""
        done
    fi
}

create_daily_backup
create_snapshot
truncate_snapshots