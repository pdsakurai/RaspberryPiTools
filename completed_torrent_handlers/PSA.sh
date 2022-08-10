#!/bin/bash

function process_movie() {
    #Expected structure:
    # Movie (2022) HEVC-PSA
    #    /Movie (2022) HEVC-PSA.mkv
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