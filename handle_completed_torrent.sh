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

#Commands
readonly is_debug_mode=true
if [[ $is_debug_mode == true ]]; then
    function noop() {
        local -r nothing=""
    }
    readonly cmd_create_directory=noop
    readonly cmd_delete=noop
    readonly cmd_rename=noop
    readonly cmd_move=noop
else
    readonly cmd_create_directory=mkdir
    readonly cmd_delete=rm
    readonly cmd_rename=mv
    readonly cmd_move=mv
fi

############

function log() {
    local text="$( [[ "$is_debug_mode" == "true" ]] && printf "!DEBUG MODE! " )${@:?Cannot do empty logging}"
    local -r tag="$FILE_NAME[$$]"
    local -r time_now="$( date "+%Y-%m-%dT%H:%M:%S" )"
    logger -t "$tag" "$text"

    touch $log_file
    sed -i "1 s|^|<$time_now> $tag: $text\n|" "$log_file"
}

function get_base_directory() {
    local full_path="${1:?Missing: Full file/folder path}"
    full_path="${full_path%/}"

    local slashes="${full_path#/}"
    slashes="${slashes//[^\/]/}"

    [[ "${#slashes}" -gt 0 ]] \
        && printf "${full_path%/*}/" \
        || printf ""
}

function get_file_extension() {
    local -r full_path="${1:?Missing: Full file/folder path}"
    local -r file_extension="${full_path##*.}"

    [[ -f "${full_path%/}" && "${#file_extension}" -gt 0 ]] \
        && printf ".$file_extension" \
        || printf ""
}

function rename() {
    local full_path="${1:?Missing: Full file/folder path}"
    local -r new_name="${2:?Missing: New name}"

    if [[ ! -e "$full_path" ]]; then
        log "Cannot rename non-existing item: \"$full_path\""
        return 1
    fi

    if [[ "${new_name//\//}" != "$new_name" ]]; then
        log "Cannot rename \"$full_path\" to an invalid name: \"$new_name\""
        return 1
    fi

    [[ -f "${full_path%/}" ]] \
        && local -r what="file" \
        || local -r what="folder"

    local -r base_directory"=$( get_base_directory "$full_path" )"
    local -r file_extension=[[ -z "$( get_file_extension "$new_name" )" ]] && "$( get_file_extension "$full_path" )"
    local -r new_full_file_path="$base_directory$new_name$file_extension"

    if [[ -e "$new_full_file_path" ]]; then
        log "Cannot rename \"$full_path\" to an existing $what: \"$new_name\""
        return 1
    fi

    $cmd_rename "${full_path%/}" "$new_full_file_path"
    log "Renamed $what: \"$full_path\" to \"$new_name\""
    printf "$new_full_file_path"
    return 0
}

function move() {
    local -r source="${1:?Missing: Source}"
    local -r destination="${2:?Missing: Destination}"

    $cmd_create_directory --parents "$destination"

    local what=""
    if [[ -d "$source" ]]; then
        local -r folder_name="${source##*/}"
        local -r complete_destination="$destination/$folder_name"
        $cmd_create_directory --parents "$complete_destination"
        local file_name
        for file_name in $( ls "$source" ); do
            $cmd_move --force --strip-trailing-slashes "$source/$file_name" "$complete_destination"
        done
        $cmd_delete --recursive --force "$source"
        what="folder"
    elif [[ -f "$source" ]]; then
        $cmd_move --force --strip-trailing-slashes "$source" "$destination"
        what="file"
    fi

    if [[ -e "$source" ]]; then
        log "Cannot move $what: \"$source\" to \"$destination\""
        return 1
    fi

    log "Moved $what: \"$source\" to \"$destination\""
    return 0
}

function delete() {
    local -r entry=${1:?Missing: Entry to delete}

    local type=""
    if [[ -f "$entry" ]]; then
        $cmd_delete "$entry"
        type="file"
    elif [[ -d "$entry" ]]; then
        $cmd_delete --recursive --force "$entry"
        type="folder"
    fi

    if [[ -e "$entry" ]]; then
        log "Cannot delete $type: \"$entry\""
        return 1
    else
        log "Deleted $type: \"$entry\""
        return 0
    fi
}

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