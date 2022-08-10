#!/bin/bash

log() {
    local tag="$FILE_NAME[$$]"
    echo "$tag: ${@:?Cannot do empty logging}"
    logger -t "$tag" "$@"
}

function cmd_sql_gravity {
    sudo sqlite3 /etc/pihole/gravity.db "${1:?Missing ${FUNCNAME[0]}.arg1: SQL statement}"
}

function get_client_ids {
    cmd_sql_gravity "select id from 'client' where comment like '%${1:?Missing ${FUNCNAME[0]}.arg1: client hostname}%'"
}

function get_group_id {
    cmd_sql_gravity "select id from 'group' where name='${1:?Missing ${FUNCNAME[0]}.arg1: group name}';"
}

function tag_client_to_group {
    cmd_sql_gravity "insert into 'client_by_group' (client_id, group_id) values (${1:?Missing ${FUNCNAME[0]}.arg1: client ID}, ${2:?Missing ${FUNCNAME[0]}.arg2: group ID});" 2> /dev/null

    [ $? -ne 0 ] && log "Warning: Client is already in the group."
}

function untag_client_from_group {
    local changes_count=$( cmd_sql_gravity "delete from 'client_by_group' where client_id=${1:?Missing ${FUNCNAME[0]}.arg1: client ID} and group_id=${2:?Missing ${FUNCNAME[0]}.arg2: group ID}; select changes();" 2> /dev/null )

    [ $changes_count -eq 0 ] && log "Warning: Client is already not in the group."
}

function update_group_status {
    local group_name=${1:?Missing ${FUNCNAME[0]}.arg1: group name}
    local new_status="${2:?Missing ${FUNCNAME[0]}.arg2: new status}"

    new_status=$( normalize_state "$new_status" )
    [ $? -ne 0 ] && return 1

    local changes_count=$( cmd_sql_gravity "update 'group' set enabled=$new_status where name='$group_name' and enabled!=$new_status; select changes();" )
    [ $changes_count -eq 0 ] && log "Warning: Nothing was updated."
}

function normalize_state {
    local state=${1:?Missing ${FUNCNAME[0]}.arg1: state}

    case $state in
        off|Off|OFF|0) state=0 ;;
        on|On|ON|1)    state=1 ;;
        *)             log "Error: Invalid input state: $state" && return 1 ;;
    esac

    prtinf "$state"
    return 0
}

function apply_changes {
    sudo /usr/local/bin/pihole restartdns reload-lists &> /dev/null
}

function modify_client_group_tagging {
    local operation="${1:?Missing ${FUNCNAME[0]}.arg1: operation [tag/untag]}"
    local client_hostnames="${2:?Missing ${FUNCNAME[0]}.arg2: client hostnames separated by space}"
    local group_id="$( get_group_id "${3:?Missing ${FUNCNAME[0]}.arg3: group name to assign}" )"


    local client_ids
    for client_hostname in $client_hostnames; do
        client_ids="$client_ids $( get_client_ids "$client_hostname" )"
    done

    [ -z "$group_id" ] && log "Error: Group not found." && return 1
    [ -z "$client_ids" ] && log "Error: Client not found." && return 1
    
    for client_id in $client_ids; do
        case $operation in
            tag)    tag_client_to_group "$client_id" "$group_id" ;;
            untag)  untag_client_from_group "$client_id" "$group_id" ;;
            *)      log "Error: Invalid input operation: $" && return 1 ;;
        esac
    done

    return 0
}

case ${1:?Missing arg1: operation} in
    add_client_into_group)      modify_client_group_tagging "tag" "$2" "$3" ;;
    remove_client_from_group)   modify_client_group_tagging "untag" "$2" "$3" ;;
    update_group_status)        update_group_status "$2" "$3" ;;
    *)                          log "Error: Unsupported input operation: $operation" && return 1 ;;
esac

[ $? -eq 0 ] && apply_changes && log "Info: Operation succeeded." || log "Error: Operation failed."