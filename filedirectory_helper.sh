#!/bin/bash

[ -n "$_filedirectory_helper_sh" ] \
    && return \
    || readonly _filedirectory_helper_sh="filedirectory_helper.sh[$$]"

if [[ -n "$is_debug_mode" ]]; then
    function noop() {
        local -r nothing=""
    }
    readonly cmd_create_directory=noop
    readonly cmd_remove_directory=noop
    readonly cmd_delete=noop
    readonly cmd_rename=noop
    readonly cmd_move=noop
else
    readonly cmd_create_directory=mkdir
    readonly cmd_remove_directory=rmdir
    readonly cmd_delete=rm
    readonly cmd_rename=mv
    readonly cmd_move=mv
fi

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
    local -r full_path="${1:?Missing: Full file/folder path}"
    local new_name="${2:?Missing: New name}"

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

    local -r file_extension="$( [[ -z "$( get_file_extension "$new_name" )" ]] && get_file_extension "$full_path" )"
    new_name="$new_name$file_extension"

    local -r base_directory"=$( get_base_directory "$full_path" )"
    local -r new_full_file_path="$base_directory$new_name"
    if [[ -e "$new_full_file_path" ]]; then
        log "Cannot rename \"$full_path\" to an existing $what: \"$new_name\""
        return 1
    fi

    $cmd_rename "${full_path%/}" "$new_full_file_path"
    log "Renamed $what: \"$full_path\" to \"$new_name\""
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
        while read file_name; do
            $cmd_move --force --strip-trailing-slashes "$source/$file_name" "$complete_destination"
        done <<< $( ls -1A "$source" )
        $cmd_delete --recursive "$source"
        what="folder"
    elif [[ -f "$source" ]]; then
        $cmd_move --force --strip-trailing-slashes "$source" "$destination"
        what="file"
    fi

    if [[ -z "$what" ]]; then
        log "Cannot move: \"$source\" to \"$destination\""
        return 1
    fi

    log "Moved $what: \"$source\" to \"$destination\""
    return 0
}

function delete() {
    local -r entry=${1:?Missing: Entry to delete}
    local -r quite_mode="$2"

    local type=""
    if [[ -f "$entry" ]]; then
        $cmd_delete "$entry"
        type="file"
    elif [[ -d "$entry" ]]; then
        local item
        while read item; do
            delete "$item" "quite_mode"
        done <<< $( ls -1A "$entry" )
        $cmd_remove_directory "$entry"
        type="folder"
    fi

    if [[ -e "$entry" ]]; then
        [[ -z "$quite_mode" ]] && log "Cannot delete $type: \"$entry\""
        return 1
    else
        [[ -z "$quite_mode" ]] && log "Deleted $type: \"$entry\""
        return 0
    fi
}