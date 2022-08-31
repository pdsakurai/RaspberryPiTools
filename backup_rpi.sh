#!/bin/bash

readonly root_directory="/mnt/eHDD/Software/Devices/Raspberry Pi 3 B+"
readonly snapshot_directory="$root_directory/Snapshots"
readonly script_backup="$root_directory/bkup_rpimage/bkup_rpimage.sh"
readonly script_shrink="$root_directory/PiShrink/pishrink.sh"
readonly daily_backup_fullfilepath="$root_directory/rpi_backup.img"

readonly debug_mode=
readonly forced_shrink=
readonly log_file="$root_directory/log.txt"


function log() {
    local -r tag="backup_rpi.sh[$$]"
    local text="$( [[ -n "$debug_mode" ]] && printf "!DEBUG MODE! " )${@:?Cannot do empty logging}"
    local -r time_now="$( date "+%Y-%m-%dT%H:%M:%S.%3N" )"
    logger -t "$tag" "$text"

    text="<$time_now> $tag: $text\n"
    [[ -e "$log_file" ]] \
        && sed -i "1 s|^|$text|" "$log_file" \
        || printf "$text" > "$log_file"
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

function do_daily_backup() {
    SECONDS=0
    [[ -z $debug_mode ]] && sudo bash "$script_backup" start -c "$daily_backup_fullfilepath"

    local -r elapsed_time="$( print_elapsed_time )"
    local file_size="$( stat -c%s "$daily_backup_fullfilepath" )"
    file_size="$( byte_to_gigabyte "$file_size" )"

    log "Completed the ${file_size}GB backup within $elapsed_time @ \"${daily_backup_fullfilepath}\"."
}

function create_snapshot() {
    local snapshot_filename="${daily_backup_fullfilepath%.img}_$(date +%Y-%m-%d).img"
    local snapshot_fullfilepath="$snapshot_directory/$snapshot_filename"

    if [[ $(date +%d) == "01" || $(date +%d) == "16" || -n "$forced_shrink" ]] \
        && [[ $( ls -1A "$snapshot_directory" | grep -c "$snapshot_filename" 2> /dev/null ) -eq 0 ]]; then
        SECONDS=0
        [[ -z $debug_mode ]] && sudo bash "$script_shrink" -Z "$daily_backup_fullfilepath" "$snapshot_fullfilepath"
        local -r elapsed_time="$( print_elapsed_time )"

        snapshot_filename="$( ls -1A "$snapshot_directory" | grep "$snapshot_filename" 2> /dev/null )"
        snapshot_fullfilepath="$snapshot_directory/$snapshot_filename"
        if [[ -z "$snapshot_filename" || ! -f "$snapshot_fullfilepath" ]]; then
            log "Failed to create snapshot @ \"${snapshot_fullfilepath}\" based on \"${daily_backup_fullfilepath}\"."
            exit 1
        fi
    
        local snapshot_filesize="$( stat -c%s "$snapshot_fullfilepath" )"
        local delta="$( stat -c%s "$daily_backup_fullfilepath" )"
        delta="$( get_delta "$snapshot_filesize" "$delta" )"
        snapshot_filesize="$( byte_to_gigabyte "$snapshot_filesize" )"

        log "Created the snapshot and shrank it by ${delta}% to ${snapshot_filesize}GB within ${elapsed_time} @ \"${snapshot_fullfilepath}\"."
    fi
}

function truncate_snapshots() {
    local -r snapshots_count=$( ls -1A "$snapshot_directory" | grep -c "rpi_backup_" )
    local -r max_snapshots_count="12"

    if [[ $snapshots_count -gt $max_snapshots_count ]]; then
        local -r snapshots_to_delete_count="$(( snapshots_count - max_snapshots_count ))"

        ls -1AX "$snapshot_directory" | head -$snapshots_to_delete_count | while read item; do
            local old_snapshot="$snapshot_directory/$item"
            [[ -z $debug_mode ]] && rm "$old_snapshot"
            log "Removed old snapshot: \"$old_snapshot\""
        done
    fi
}

do_daily_backup
create_snapshot
truncate_snapshots