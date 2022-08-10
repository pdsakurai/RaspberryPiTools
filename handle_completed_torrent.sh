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
readonly keywordInTorrentNameForPsa="HEVC-PSA"
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
readonly debugMode=false
if [[ $debugMode == true ]]; then
    doNothing(){
        local -r nothing=""
    }
    readonly createDirectoryCommand=doNothing
    readonly deleteCommand=doNothing
    readonly renameCommand=doNothing
    readonly moveCommand=doNothing
else
    readonly createDirectoryCommand=mkdir
    readonly deleteCommand=rm
    readonly renameCommand=mv
    readonly moveCommand=mv
fi

############

log(){
    local -r message=$1
    local -r timeNow=$(date "+%Y-%m-%dT%H:%M:%S")
    
    touch $logFile
    if [[ $debugMode == true ]]; then
        echo "<$timeNow> [DEBUG MODE] $message" >> $logFile
    else
        echo "<$timeNow> $message" >> $logFile
    fi
}

move(){
    local -r sourceFullPath=$1
    local -r destinationDirectory=$2

    $createDirectoryCommand --parents "$destinationDirectory"

    what=""
    if [[ -d "$sourceFullPath" ]]; then
        local -r folderName="${sourceFullPath##*/}"
        local -r completeDestinationDirectory="$destinationDirectory/$folderName"
        $createDirectoryCommand --parents "$completeDestinationDirectory"
        for fileName in $( ls "$sourceFullPath" ); do
            $moveCommand --force --strip-trailing-slashes "$sourceFullPath/$fileName" "$completeDestinationDirectory"
        done
        $deleteCommand --recursive --force "$sourceFullPath"
        what="folder"
    elif [[ -f "$sourceFullPath" ]]; then
        $moveCommand --force --strip-trailing-slashes "$sourceFullPath" "$destinationDirectory"
        what="file"
    fi

    if [[ -e "$sourceFullPath" ]] || [[ -d "$sourceFullPath" ]]; then
        log "Cannot move $what: \"$sourceFullPath\" to \"$destinationDirectory\""
    else
        log "Moved $what: \"$sourceFullPath\" to \"$destinationDirectory\""
    fi
}

delete(){
    local -r fullFileOrFolderPath=$1

    what=""
    if [[ -f "$fullFileOrFolderPath" ]]; then
        $deleteCommand "$fullFileOrFolderPath"
        what="file"
    elif [[ -d "$fullFileOrFolderPath" ]]; then
        $deleteCommand --recursive --force "$fullFileOrFolderPath"
        what="folder"
    fi

    if [[ -e "$fullFileOrFolderPath" ]] || [[ -d "$fullFileOrFolderPath" ]]; then
        log "Cannot delete $what: \"$fullFileOrFolderPath\""
    else
        log "Deleted $what: \"$fullFileOrFolderPath\""
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
    $renameCommand "$baseDirectory/$originalFileNameWithExtension" "$baseDirectory/$newFileName"
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

renameDownloadedMovieFromPSA(){
    local -r originalTorrentPath=${1%/}

    local -r originalFolderName=${originalTorrentPath##*/}
    local -r baseDirectory=${originalTorrentPath%/$originalFolderName}
    local -r cleanedFolderName=$( \
        echo ${originalFolderName//./ } \
        | sed "s/.\(108\|72\)0p.*$//" \
        | sed "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)/" )

    for fileNameWithExtension in $( ls "$originalTorrentPath" ); do
        if [[ -f "$originalTorrentPath/$fileNameWithExtension" ]]; then
            if [[ ${fileNameWithExtension%.*} = $originalFolderName ]]; then
                local fileExtension=${fileNameWithExtension##*.}
                local newFileName="$cleanedFolderName.$fileExtension"
                $renameCommand "$originalTorrentPath/$fileNameWithExtension" "$originalTorrentPath/$newFileName"
                log "Renamed file: \"$originalTorrentPath/$fileNameWithExtension\" to \"$newFileName\""
            else
                delete "$originalTorrentPath/$fileNameWithExtension"
            fi
        fi
    done

    $renameCommand "$baseDirectory/$originalFolderName" "$baseDirectory/$cleanedFolderName"
    log "Renamed folder: \"$baseDirectory/$originalFolderName\" to \"$cleanedFolderName\""

    echo "$baseDirectory/$cleanedFolderName"
}

renameDownloadedTvShowFromPSA(){
    local -r originalTorrentPath=$1

    local -r optionsForSedChainedCommand=( \
        "s/\./ /g" \
        "s/\(S[0-9]\+E[0-9]\+\).*$/\1/" )

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

processDownloadedMovieFromPSA(){
    local -r originalTorrentPath=$1

    local -r renamedFullFolderPath=$( renameDownloadedMovieFromPSA "$originalTorrentPath" )

    move "$renamedFullFolderPath" "$directoryMovie"
}

processDownloaded3DMovieFromPSA(){
    local -r originalTorrentPath=$1

    local -r renamedFullFolderPath=$( renameDownloadedMovieFromPSA "$originalTorrentPath" )

    local -r renamedFolderName=${renamedFullFolderPath##*/}
    for fileNameWithExtension in $( ls "$renamedFullFolderPath" ); do
        if [[ -f "$renamedFullFolderPath/$fileNameWithExtension" ]] && [[ ${fileNameWithExtension%.*} = $renamedFolderName ]]; then
            move "$renamedFullFolderPath/$fileNameWithExtension" "$directoryMovie3D"
        fi
    done

    delete "$renamedFullFolderPath"
}

processDownloadedTvShowFromPSA(){
    local -r originalTorrentPath=$1

    local -r renamedFullFilePath=$( renameDownloadedTvShowFromPSA "$originalTorrentPath" )
    local -r tvShowTitle=$( \
       echo ${renamedFullFilePath##*/} \
       | sed "s/ S[0-9]\+E[0-9]\+.*$//" )

    move "$renamedFullFilePath" "$directoryTvShow/$tvShowTitle"
}

isFileNameTaggedWithSeasonAndEpisode() {
    local -r l_fileName=$1

    if [[ $l_fileName =~ S[0-9]+E[0-9]+ ]]; then
        return 0
    fi

    return 1
}

############


if [[ ${torrentPath##*/} == *$keywordInTorrentNameForPsa* ]]; then

    if [[ -d "$torrentPath" ]]; then
        readonly regexFor3DMovies=\\b3D\\b.+SBS\\b
        if [[ ${torrentPath##*/} =~ $regexFor3DMovies ]]; then
            processDownloaded3DMovieFromPSA "$torrentPath"
        else
            processDownloadedMovieFromPSA "$torrentPath"
        fi
    fi

    if [[ -f "$torrentPath" ]] && isFileNameTaggedWithSeasonAndEpisode "${torrentPath##*/}"; then
        processDownloadedTvShowFromPSA "$torrentPath"
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
