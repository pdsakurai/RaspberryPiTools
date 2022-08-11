#!/bin/bash

#Provided by Transmission
readonly torrentDir="$TR_TORRENT_DIR"
readonly torrentName="$TR_TORRENT_NAME"

set -euo pipefail
IFS=$'\n\t'

#Constants
readonly keywordInTorrentNameForJudas="Judas"
readonly keywordInTorrentNameForYakuboEncodes="YakuboEncodes"
readonly keywordInTorrentNameForHorribleSubs="HorribleSubs"
if [[ -n $torrentDir  ]] && [[ -n $torrentName ]]; then
    readonly torrentPath="$torrentDir/$torrentName"
else
    readonly torrentPath=${1:?Torrent path is not known.}
fi

#Environment
readonly dir_root="/mnt/eHDD/Videos"
readonly dir_anime="$dir_root/Anime"
readonly dir_movie="$dir_root/Movie"
readonly dir_tvshow="$dir_root/TV show"
readonly log_file="/mnt/eHDD/Torrent/log.txt"

. ./completed_torrent_handlers/PSA.sh
if is_from_PSA "$torrentPath"; then
    if is_a_tvshow "$torrentPath"; then
        process_tvshow "$torrentPath" "$dir_tvshow"
        exit 0
    elif [[ -d "$torrentPath" ]]; then
        process_movie "$torrentPath" "$dir_movie"
        exit 0
    fi
fi

#mv "$torrentPath" "${torrentPath%/*}/[Judas] ${torrentPath##*/}"
#find "/mnt/eHDD/Torrent/" -maxdepth 1 -type f -execdir bash /mnt/eHDD/Scripts/processCompletedTorrents.sh '{}' \;

# Scrapers' rules for TV shows
# 1. Special episodes must have S00 as its season.
# 2. If absolute episode numbering is used or there is no season, prefix must be "ep". Example: ep01 which means episode 1.
# 3. If there is season, format must be S00E00. Example: S01E01 which means episode 1 of season 1.