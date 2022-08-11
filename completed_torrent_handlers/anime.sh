#!/bin/bash

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

readonly keywordInTorrentNameForJudas="Judas"
readonly keywordInTorrentNameForYakuboEncodes="YakuboEncodes"
readonly keywordInTorrentNameForHorribleSubs="HorribleSubs"
if [[ ${torrent_path##*/} == *$keywordInTorrentNameForJudas* ]] \
   || [[ ${torrent_path##*/} == *$keywordInTorrentNameForYakuboEncodes* ]] \
   || [[ ${torrent_path##*/} == *$keywordInTorrentNameForHorribleSubs* ]]; then

    if [[ -f "$torrent_path" ]]; then
        if [[ ${torrent_path##*/} =~ \ -\ [0-9]+ ]] || isFileNameTaggedWithSeasonAndEpisode "${torrent_path##*/}"; then
            processDownloadedAnimeFromJudas "$torrent_path" "$dir_anime"
        else
            processDownloadedAnimeFromJudas "$torrent_path" "$dir_movie"
        fi
    fi

fi