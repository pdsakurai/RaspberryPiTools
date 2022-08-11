#!/bin/bash

[ -n "$_PSA_sh" ] \
    && return \
    || readonly _PSA_sh="$FILE_NAME[$$]"

function is_from_PSA() {
    local -r torrent_path="${1:?Missing: Torrent path}"

    [[ "${torrent_path##*/}" =~ .HEVC-PSA. ]] && return 0
    return 1
}

function is_a_tvshow() {
    local -r torrent_path="${1:?Missing: Torrent path}"
    local -r item="${torrent_path##*/}"
    [[ -f "$torrent_path" ]] && [[ "$item" =~ .S[[:digit:]]+E[[:digit:]]+. ]] && return 0
    [[ -d "$torrent_path" ]] && [[ "$item" =~ .S[[:digit:]]+.COMPLETE. ]] && return 0
    return 1
}

function clean_text_using_sed() {
    local text="${1:?Missing: text to clean}"
    local -r custom_sed_options_sequence=( "${!2}" )

    : 'Common sed options sequence remarks
    Line 1 - removal of tags text, starting from resolution tag going to the right
    Line 2 - enclosing of year released with pair of parentheses
    Line 3 - changing dot separator to whitespace'
    local -r common_sed_options_sequence=( \
        "s/.\(216\|108\|72\)0p.*$//" \
        "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)\2/" \
        "s/\./ /g" )

    local sed_option
    for sed_option in "${common_sed_options_sequence[@]}" "${custom_sed_options_sequence[@]}"; do
        text="$( printf "$text" | sed "$sed_option" )"
    done

    printf "$text" | xargs
}

function process_movie() {
    : 'Expected structure:
    Folder: Movie.2022.EXTENDED.1080p.*HEVC-PSA
    Inside it:
        Movie.2022.EXTENDED.1080p.*HEVC-PSA.mkv
        .*other irrelevant files.*'
    local -r torrent_path="${1%/}"
    local -r destination="${2:?Missing: Destination}"

    local -r folder_name_original="${torrent_path##*/}"
    local -r folder_name_cleaned="$( clean_text_using_sed "$folder_name_original" ( "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)/" ) )"
    local entry_name
    for entry_name in $( ls "$torrent_path" ); do
        local -r entry_full_file_path="$torrent_path/$entry_name"
        if [[ -f "$torrent_path/$entry_name" ]] && [[ "${entry_name%.*}" == "$folder_name_original" ]]; then
            rename "$entry_full_file_path" "$folder_name_cleaned"
        else
            delete "$entry_full_file_path"
        fi
    done

    local -r cleaned_torrent_path="$( rename "$torrent_path" "$folder_name_cleaned" )"
    move "$cleaned_torrent_path" "$destination"
}

function process_tvshow(){
    local -r torrent_path="${1%/}"
    local -r destination="${2:?Missing: Destination}"

    : 'Expected structure #1:
    TV.Show.2022.S01E01.Title.of.episode.720p.+*HEVC-PSA.mkv'
    if [[ -f "$torrent_path" ]]; then
        local -r file_name_cleaned="$( clean_text_using_sed "${torrent_path##*/}" )"
        local -r cleaned_torrent_path="$( rename "$torrent_path" "$file_name_cleaned" )"
        local -r tv_show_title="$( printf "${cleaned_torrent_path##*/}" | sed "s/.S[0-9]\+E[0-9]\+.*//" )"
        move "$cleaned_torrent_path" "$destination/$tv_show_title"

    : 'Expected structure #2:
    Folder: TV.Show.2022.SEASON.01.S01.COMPLETE.720p.+HEVC-PSA
    Inside it:
        TV.Show.2022.S01E01.Title.of.episode.720p.+*HEVC-PSA.mkv
        TV.Show.2022.S01E02.Title.of.episode.720p.+*HEVC-PSA.mkv'
    elif [[ -d "$torrent_path" ]]; then
        local -r tv_show_title="$( printf "${torrent_path##*/}" | sed "s/\.SEASON\..\+//" )"

        local file_name
        local has_processed_tvshow
        for file_name in "$( ls "$torrent_path" )"; do
            if [[ -f "$torrent_path/$file_name" ]] && [[ "$file_name" =~ ^$tv_show_title ]]; then 
                process_tvshow "$torrent_path/$file_name" "$destination"
                has_processed_tvshow="true"
            fi
        done

        [[ -n "$has_processed_tvshow" ]] && delete "$torrent_path"
    fi
}