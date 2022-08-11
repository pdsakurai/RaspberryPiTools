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
readonly directoryRoot="/mnt/eHDD/Videos"
readonly directoryAnime="$directoryRoot/Anime"
readonly directoryMovie="$directoryRoot/Movie"
readonly directoryMovie3D="$directoryRoot/Movie - 3D"
readonly directoryTvShow="$directoryRoot/TV show"
readonly logFile="/mnt/eHDD/Torrent/log.txt"

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

    touch $logFile
    sed -i "1 s|^|<$time_now> $tag: $text\n|" "$logFile"
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

move(){
    local -r sourceFullPath=$1
    local -r destinationDirectory=$2

    $cmd_create_directory --parents "$destinationDirectory"

    what=""
    if [[ -d "$sourceFullPath" ]]; then
        local -r folderName="${sourceFullPath##*/}"
        local -r completeDestinationDirectory="$destinationDirectory/$folderName"
        $cmd_create_directory --parents "$completeDestinationDirectory"
        for fileName in $( ls "$sourceFullPath" ); do
            $cmd_move --force --strip-trailing-slashes "$sourceFullPath/$fileName" "$completeDestinationDirectory"
        done
        $cmd_delete --recursive --force "$sourceFullPath"
        what="folder"
    elif [[ -f "$sourceFullPath" ]]; then
        $cmd_move --force --strip-trailing-slashes "$sourceFullPath" "$destinationDirectory"
        what="file"
    fi

    if [[ -e "$sourceFullPath" ]] || [[ -d "$sourceFullPath" ]]; then
        log "Cannot move $what: \"$sourceFullPath\" to \"$destinationDirectory\""
    else
        log "Moved $what: \"$sourceFullPath\" to \"$destinationDirectory\""
    fi
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

renameDownloadedFile(){
    local -r originalTorrentPath=$( echo $1 | sed "s/\/$//" )
    local customOptionsForSedChainedCommand=( "${!2}" )

    local -r originalFileNameWithExtension=${originalTorrentPath##*/}
    local -r fileExtension=${originalFileNameWithExtension##*.}
    local -r originalFileNameWithoutExtension=${originalFileNameWithExtension%.$fileExtension}

    local cleanedFileNameWithoutExtension=$originalFileNameWithoutExtension

    local -r cleanupOptionsForSedChainedCommand=( \
        "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)\2/" \
        "s/^ \+//" \
        "s/ \+$//" )

    for sedOption in "${customOptionsForSedChainedCommand[@]}" "${cleanupOptionsForSedChainedCommand[@]}"; do
        cleanedFileNameWithoutExtension=$(echo $cleanedFileNameWithoutExtension | sed "$sedOption")
    done

    local -r baseDirectory=${originalTorrentPath%/*}
    local -r newFileName="$cleanedFileNameWithoutExtension.$fileExtension"
    $cmd_rename "$baseDirectory/$originalFileNameWithExtension" "$baseDirectory/$newFileName"
    log "Renamed file: \"$baseDirectory/$originalFileNameWithExtension\" to \"$newFileName\""

    echo "$baseDirectory/$newFileName"
}

renameDownloadedAnimeFromJudas(){
    local -r originalTorrentPath=$1

    local -r optionsForSedChainedCommand=( \
        "s/\[[A-Za-z0-9 \-]\+\]//g" \
        "s/ - \([0-9]\+\).*$/ ep\1/" \
        "s/ - \(S[0-9]\+E[0-9]\+\).*$/ \1/" \
        "s/ - Movie [0-9]\+ -//" )

    echo $(renameDownloadedFile "$originalTorrentPath" optionsForSedChainedCommand[@])
}

processDownloadedAnimeFromJudas(){
    local -r originalTorrentPath=$1
    local -r destinationDirectory=$2

    local -r renamedFullFilePath=$( renameDownloadedAnimeFromJudas "$originalTorrentPath" )

    local -r animeTitle=$( \
        echo ${renamedFullFilePath##*/} \
        | sed "s/\.[a-zA-Z0-9]\+$//" \
        | sed "s/ ep[0-9]\+.*$//" \
        | sed "s/ S[0-9]\+E[0-9]\+.*$//" )

    move "$renamedFullFilePath" "$destinationDirectory/$animeTitle"
}

isFileNameTaggedWithSeasonAndEpisode() {
    local -r l_fileName=$1

    if [[ $l_fileName =~ S[0-9]+E[0-9]+ ]]; then
        return 0
    fi

    return 1
}

############


    . ./completed_torrent_handlers/PSA.sh

if is_from_PSA "$torrentPath"; then
    if is_a_tvshow "$torrentPath"; then
        process_tvshow "$torrentPath"
        exit 0
    elif [[ -d "$torrentPath" ]]; then
        process_movie "$torrentPath"
        exit 0
    fi
fi

if [[ ${torrentPath##*/} == *$keywordInTorrentNameForJudas* ]] \
   || [[ ${torrentPath##*/} == *$keywordInTorrentNameForYakuboEncodes* ]] \
   || [[ ${torrentPath##*/} == *$keywordInTorrentNameForHorribleSubs* ]]; then

    if [[ -f "$torrentPath" ]]; then
        if [[ ${torrentPath##*/} =~ \ -\ [0-9]+ ]] || isFileNameTaggedWithSeasonAndEpisode "${torrentPath##*/}"; then
            processDownloadedAnimeFromJudas "$torrentPath" "$directoryAnime"
        else
            processDownloadedAnimeFromJudas "$torrentPath" "$directoryMovie"
        fi
    fi

fi

command


#mv "$torrentPath" "${torrentPath%/*}/[Judas] ${torrentPath##*/}"
#find "/mnt/eHDD/Torrent/" -maxdepth 1 -type f -execdir bash /mnt/eHDD/Scripts/processCompletedTorrents.sh '{}' \;

# Scrapers' rules for TV shows
# 1. Special episodes must have S00 as its season.
# 2. If absolute episode numbering is used or there is no season, prefix must be "ep". Example: ep01 which means episode 1.
# 3. If there is season, format must be S00E00. Example: S01E01 which means episode 1 of season 1.
