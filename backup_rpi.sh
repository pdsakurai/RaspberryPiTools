#!/bin/bash

readonly backup_directory="/mnt/eHDD/Software/Devices/Raspberry Pi 3 B+"
readonly script_backup="$backup_directory/bkup_rpimage/bkup_rpimage.sh"
readonly script_shrink="$backup_directory/PiShrink/pishrink.sh"

readonly debug_mode=
readonly forced_shrink=
readonly log_file="$backup_directory/log.txt"


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

change_seconds_to_text() {
    local display_seconds=$1

    local -r seconds_in_one_hour=3600
    local -r display_hours=$(( display_seconds / seconds_in_one_hour ))
    display_seconds=$(( display_seconds % seconds_in_one_hour ))

    local -r seconds_in_one_minute=60
    local -r display_minutes=$(( display_seconds / seconds_in_one_minute ))
    display_seconds=$(( display_seconds % seconds_in_one_minute ))

    printf "%02d:%02d:%02d" $display_hours $display_minutes $display_seconds
}

absolute() {
    local number=$1

    [[ $number -lt 0 ]] && number=$(( number * -1 ))

    echo $number
}

get_delta() {
    local -r numerator=$1
    local -r denominator=$2
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

to_gigabyte() {
    local -r bytes=$1

    local -r bytes_in_one_gigabyte=$(( 10**9 ))
    local -r precision=$(( bytes_in_one_gigabyte / 10**2 ))

    local -r whole_number=$(( bytes / bytes_in_one_gigabyte ))
    local -r fractional_number=$(( (bytes%(whole_number*bytes_in_one_gigabyte)) / precision ))

    printf "%d.%02d" $whole_number $fractional_number
}

readonly daily_backup_filename="rpi_backup.img"
readonly daily_backup_full_filepath="$backup_directory/$daily_backup_filename"

SECONDS=0
[[ -z $debug_mode ]] && sudo bash "$script_backup" start -c "$daily_backup_full_filepath"
readonly duration_backup=$SECONDS

readonly file_size_in_bytes_daily_backup=$( stat -c%s "$daily_backup_full_filepath" )
log "Completed the $( to_gigabyte $file_size_in_bytes_daily_backup )GB backup within $( change_seconds_to_text $duration_backup ): \"$daily_backup_full_filepath\"."

readonly bimonthly_backup_filename="rpi_backup_$(date +%Y-%m-%d).img"
readonly bimonthly_backup_directory="$backup_directory/Snapshots"
readonly bimonthly_backup_full_filepath="$bimonthly_backup_directory/$bimonthly_backup_filename"

if [[ $(date +%d) == "01" || $(date +%d) == "16" || -n "$forced_shrink" ]] && [[ ! -e $bimonthly_backup_full_filepath ]]; then
    SECONDS=0
    [[ -z $debug_mode ]] && sudo bash "$script_shrink" -z "$daily_backup_full_filepath" "$bimonthly_backup_full_filepath"
    readonly duration_shrinking_backup=$SECONDS

    readonly file_size_in_bytes_bimonthly_backup=$( stat -c%s "$bimonthly_backup_full_filepath.gz" )
    log "Created snapshot and shrinked it by $( get_delta $file_size_in_bytes_bimonthly_backup $file_size_in_bytes_daily_backup )% to $( to_gigabyte $file_size_in_bytes_bimonthly_backup )GB within $( change_seconds_to_text $duration_shrinking_backup ): \"$bimonthly_backup_full_filepath.gz\"."

    readonly current_number_of_bimonthly_backups=$( ls -1 "$bimonthly_backup_directory" | wc -l )
    readonly max_number_of_bimonthly_backups=12
    if [[ $current_number_of_bimonthly_backups -gt $max_number_of_bimonthly_backups ]]; then
        readonly oldest_bimonthly_backup_filename=$( ls -1 "$bimonthly_backup_directory" | head -1 )
        readonly full_filepath="$bimonthly_backup_directory/$oldest_bimonthly_backup_filename"
        [[ -z $debug_mode ]] &&  rm "full_filepath"
        log "Removed oldest backup file: \"$full_filepath\""
	fi
fi
