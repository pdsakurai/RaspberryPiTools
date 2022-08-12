#!/bin/bash

function log() {
    local -r tag="handle_completed_torrent.sh[$$]"
    local text="$( [[ -n "$is_debug_mode" ]] && printf "!DEBUG MODE! " )${@:?Cannot do empty logging}"
    local -r time_now="$( date "+%Y-%m-%dT%H:%M:%S.%3N" )"
    logger -t "$tag" "$text"

    text="<$time_now> $tag: $text\n"
    [[ -e "$log_file" ]] \
        && sed -i "1 s|^|$text|" "$log_file" \
        || printf "$text" > "$log_file"
}

#Provided by Transmission
if [[ -n "$TR_TORRENT_DIR"  ]] && [[ -n "$TR_TORRENT_NAME" ]]; then
    readonly TORRENT_PATH="$TR_TORRENT_DIR/$TR_TORRENT_NAME"
#Provided by aria2c
elif [[ -n "$1" ]] && [[ -n "$2" ]] && [[ -n "$3" ]]; then
    readonly TORRENT_PATH="$3"
elif [[ -e "$1" ]] && [[ -z "$2" ]]; then
    readonly is_debug_mode="true"
    readonly TORRENT_PATH="$1"
else
    log "No valid arguments found. Arguments[$#]: $@"
    exit 1
fi

log "Proccesing torrent path: $TORRENT_PATH"

#Environment
readonly dir_root="/mnt/eHDD/Videos"
readonly dir_anime="$dir_root/Anime"
readonly dir_movie="$dir_root/Movie"
readonly dir_tvshow="$dir_root/TV show"
readonly log_file="/mnt/eHDD/Downloads/log.txt"

. ./filedirectory_helper.sh
. ./completed_torrent_handlers/PSA.sh
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