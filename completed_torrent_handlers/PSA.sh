#!/bin/bash

function rename_file() {
    local -r full_file_path="${1:?Missing: Full file path}"
    local -r custom_sed_options_sequence=( "${!2}" )

    local -r file_name=${full_file_path##*/}
    local -r file_extension=${file_name##*.}
    local -r file_name_cleaned="$( clean_text_using_sed "${file_name%.$file_extension}" "${custom_sed_options_sequence[@]}" ).$file_extension"

    local -r base_directory=${full_file_path%/*}
    rename "$base_directory/$file_name" "$base_directory/$file_name_cleaned"

    printf "$base_directory/$file_name_cleaned"
}

function clean_text_using_sed() {
    local text="${1:?Missing: text to clean}"
    local -r custom_sed_options_sequence=( "${!2}" )

    '''Common sed options sequence remarks
    Line 1 - removal of tags text, starting from resolution tag going to the right
    Line 2 - enclosing of year released with pair of parentheses
    Line 3 - changing dot separator to whitespace '''
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
    '''Expected structure:
    Folder: Movie.2022.EXTENDED.1080p.*HEVC-PSA
    Inside it:
        Movie.2022.EXTENDED.1080p.*HEVC-PSA.mkv
        .*other irrelevant files.*'''
    local -r torrent_path=${1%/}

    local -r folder_name_original=${torrent_path##*/}
    local -r base_directory=${torrent_path%/$folder_name_original}

    local -r folder_name_cleaned=$( \
        echo ${folder_name_original//./ } \
        | sed "s/.\(108\|72\)0p.*$//" \
        | sed "s/(\?\([0-9]\{4\}\))\?\(.*$\)/\(\1)/" )

    for entry_name in $( ls "$torrent_path" ); do
        if [ ${entry_name%.*} == $folder_name_original ]; then
            local -r file_extension=${entry_name##*.}
            local -r file_name_cleaned="$folder_name_cleaned.$file_extension"
            rename "$torrent_path/$entry_name" "$torrent_path/$file_name_cleaned"
        else
            delete "$torrent_path/$entry_name"
        fi
    done

    local -r torrent_path_cleaned="$base_directory/$folder_name_cleaned"
    rename "$base_directory/$folder_name_original" "$torrent_path_cleaned"
    move "$torrent_path_cleaned" "$directoryMovie"
}

function process_tvshow(){
    '''Expected structure:
    TV.Show.2022.S01E01.Title.of.episode.*HEVC-PSA.mkv'''
    local -r torrent_path=${1%/}

    local -r full_file_path="$( rename_file "$torrent_path" )"
    local -r tv_show_title="$( printf "${full_file_path##*/}" | sed "s/.S[0-9]\+E[0-9]\+.*//" )"

    move "$full_file_path" "$directoryTvShow/$tv_show_title"
}
