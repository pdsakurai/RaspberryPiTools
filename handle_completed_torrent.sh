#!/bin/bash

function log() {
    local -r tag="handle_completed_torrent.sh[$$]"
    local text="$( [[ -n "$is_debug_mode" ]] && printf "!DEBUG MODE! " )${@:?Cannot do empty logging}"
    local -r time_now="$( date "+%Y-%m-%dT%H:%M:%S.%3N" )"
    logger -t "$tag" "$text"

    text="<$time_now> $tag: $text\n"
    local -r log_file="/mnt/eHDD/Downloads/log.txt"
    [[ -e "$log_file" ]] \
        && sed -i "1 s|^|$text|" "$log_file" \
        || printf "$text" > "$log_file"
}

#Provided by Transmission
if [[ "$#" -eq "0" && -n "$TR_TORRENT_DIR" && -n "$TR_TORRENT_NAME" ]]; then
    log "Triggered by Transmission. Arguments[$#]: $@"
    readonly TORRENT_PATH="$TR_TORRENT_DIR/$TR_TORRENT_NAME"
elif [[ "$#" -eq "1" && -e "$1" ]]; then
    # readonly is_debug_mode="true"
    readonly TORRENT_PATH="$1"
#Provided by aria2c
elif [[ "$#" -eq "3" ]]; then
    function correct_aria2c_arg_path() {
        local -r files_count=${1:?Missing: Files count}
        local first_full_file_path=${2:?Missing: First full file path}

        [[ "$files_count" -lt "1" ]] && return 1
        [[ "$files_count" -eq "1" ]] && printf "$first_full_file_path" && return 0

        first_full_file_path="${first_full_file_path%/}"
        printf "${first_full_file_path%/*}"
        return 0
    }
    log "Triggered by aria2c. Arguments[$#]: $@"
    readonly TORRENT_PATH="$( correct_aria2c_arg_path "$2" "$3" )"
fi

if [[ -z "$TORRENT_PATH" ]]; then
    log "No valid arguments found. Arguments[$#]: $@"
    exit 1
fi

log "Proccesing torrent path: $TORRENT_PATH"

#Environment
readonly dir_root="/mnt/eHDD/Videos"
readonly dir_anime="$dir_root/Anime"
readonly dir_movie="$dir_root/Movies"
readonly dir_tvshow="$dir_root/TV Series"

readonly script_location="/mnt/dietpi_userdata/GitHub/RaspberryPiTools"
source $script_location/filedirectory_helper.sh
source $script_location/completed_torrent_handlers/PSA.sh

if is_from_PSA "$TORRENT_PATH"; then
    if is_a_tvshow "$TORRENT_PATH"; then
        process_tvshow "$TORRENT_PATH" "$dir_tvshow"
        exit 0
    elif [[ -d "$TORRENT_PATH" ]]; then
        process_movie "$TORRENT_PATH" "$dir_movie"
        exit 0
    fi
fi

#mv "$TORRENT_PATH" "${TORRENT_PATH%/*}/[Judas] ${TORRENT_PATH##*/}"
#find "/mnt/eHDD/Torrent/" -maxdepth 1 -type f -execdir bash /mnt/eHDD/Scripts/processCompletedTorrents.sh '{}' \;

# Scrapers' rules for TV shows
# 1. Special episodes must have S00 as its season.
# 2. If absolute episode numbering is used or there is no season, prefix must be "ep". Example: ep01 which means episode 1.
# 3. If there is season, format must be S00E00. Example: S01E01 which means episode 1 of season 1.