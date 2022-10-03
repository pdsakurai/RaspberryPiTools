#!/bin/bash

[ -n "$_PSA_sh" ] \
    && return \
    || readonly _PSA_sh="PSA.sh[$$]"

function is_from_PSA() {
    local torrent_path="${1:?Missing: Torrent path}"
    torrent_path="${torrent_path%/}"
    [[ "${torrent_path##*/}" =~ .HEVC-PSA ]] && return 0
    return 1
}

function is_a_tvshow() {
    local torrent_path="${1:?Missing: Torrent path}"
    torrent_path="${torrent_path%/}"
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
    local -ra sed_additional_option=( "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)/" )
    local -r folder_name_cleaned="$( clean_text_using_sed "$folder_name_original" sed_additional_option[@] )"
    ls -1A "$torrent_path" | while read entry_name; do
        local entry_full_file_path="$torrent_path/$entry_name"
        if [[ -f "$torrent_path/$entry_name" ]] && [[ "${entry_name%.*}" == "$folder_name_original" ]]; then
            rename "$entry_full_file_path" "$folder_name_cleaned"
        else
            delete "$entry_full_file_path"
        fi
    done

    rename "$torrent_path" "$folder_name_cleaned"
    local -r base_directory="$( get_base_directory "$torrent_path" )"
    move "$base_directory$folder_name_cleaned" "$destination"
}

function process_tvshow(){
    local -r torrent_path="${1%/}"
    local -r destination="${2:?Missing: Destination}"

    : 'Expected structure #1:
    TV.Show.2022.S01E01.Title.of.episode.720p.+*HEVC-PSA.mkv'
    if [[ -f "$torrent_path" ]] && [[ "$torrent_path" ~= .mkv$ ]]; then
        local -r file_name_cleaned="$( clean_text_using_sed "${torrent_path##*/}" )"
        local -r base_directory="$( get_base_directory "$torrent_path" )"
        local -r file_extension="$( get_file_extension "$torrent_path" )"
        local -r tv_show_title="$( printf "$file_name_cleaned" | sed "s/.S[0-9]\+E[0-9]\+.*//" )"
        rename "$torrent_path" "$file_name_cleaned"
        move "$base_directory$file_name_cleaned$file_extension" "$destination/$tv_show_title"

    : 'Expected structure #2:
    Folder: TV.Show.2022.SEASON.01.S01.COMPLETE.720p.+HEVC-PSA
    Inside it:
        TV.Show.2022.S01E01.Title.of.episode.720p.+*HEVC-PSA.mkv
        TV.Show.2022.S01E02.Title.of.episode.720p.+*HEVC-PSA.mkv'
    elif [[ -d "$torrent_path" ]]; then
        local -r tv_show_title="$( printf "${torrent_path##*/}" | sed "s/\.SEASON\..\+//" )"

        local file_name
        local has_processed_tvshow
        while read file_name; do
            if [[ -f "$torrent_path/$file_name" ]] && [[ "$file_name" =~ ^$tv_show_title ]]; then 
                process_tvshow "$torrent_path/$file_name" "$destination"
                has_processed_tvshow="true"
            fi
        done <<< $( ls -1A "$torrent_path" )
        
        [[ -n "$has_processed_tvshow" ]] && delete "$torrent_path"
    fi
}