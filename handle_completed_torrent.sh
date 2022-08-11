#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

#Provided by Transmission
if [[ -n "$TR_TORRENT_DIR"  ]] && [[ -n "$TR_TORRENT_NAME" ]]; then
    readonly torrent_path="$TR_TORRENT_DIR/$TR_TORRENT_NAME"
else 
    readonly torrent_path=${1:?Torrent path is not known.}
fi

#Environment
readonly dir_root="/mnt/eHDD/Videos"
readonly dir_anime="$dir_root/Anime"
readonly dir_movie="$dir_root/Movie"
readonly dir_tvshow="$dir_root/TV show"
readonly log_file="/mnt/eHDD/Torrent/log.txt"

. ./completed_torrent_handlers/PSA.sh
if is_from_PSA "$torrent_path"; then
    if is_a_tvshow "$torrent_path"; then
        process_tvshow "$torrent_path" "$dir_tvshow"
        exit 0
    elif [[ -d "$torrent_path" ]]; then
        process_movie "$torrent_path" "$dir_movie"
        exit 0
    fi
fi

#mv "$torrent_path" "${torrent_path%/*}/[Judas] ${torrent_path##*/}"
#find "/mnt/eHDD/Torrent/" -maxdepth 1 -type f -execdir bash /mnt/eHDD/Scripts/processCompletedTorrents.sh '{}' \;

# Scrapers' rules for TV shows
# 1. Special episodes must have S00 as its season.
# 2. If absolute episode numbering is used or there is no season, prefix must be "ep". Example: ep01 which means episode 1.
# 3. If there is season, format must be S00E00. Example: S01E01 which means episode 1 of season 1.