#!/bin/bash

#Configuration
readonly HOST_NAME="${1:?Missing: Hostname}"
readonly SECRET_KEY="${2:?Missing: Secret key}"

#Don't edit anything below this line
log() {
    local tag="$FILE_NAME[$$]"
    echo "$tag: ${@:?Cannot do empty logging}"
    logger -t "$tag" "$@"
}

is_under_CGN() {
    local my_ip_address="${1:?Missing:IP address}"

    local result=$( traceroute "$my_ip_address" -n --max-hops=3 | tail -1 | xargs )
    local hops=$( echo $result | cut -d ' ' -f 1 )
    local ip_address=$( echo $result | cut -d ' ' -f 2 )

    if [[ "$hops" == "1" && "$my_ip_address" == "$ip_address" ]]; then
        return 1
    fi

    log "IPv4 network is under CGN."
    return 0
}

is_update_needed() {
    local ip_version="${1:?Missing: IP version}"
    local my_ip_address="$2"

    local ip_address_delimiter=$( [[ "${ip_version,,}" == "ipv4" ]] \
        && echo "\." \
        || echo ":" )
    local hostname_ip_address=$( nslookup $HOST_NAME | grep "Address" | grep -v "#" | cut -d ' ' -f 2 | grep "$ip_address_delimiter" )

    if [[ "$my_ip_address" == "$hostname_ip_address" ]]; then
        log "$HOST_NAME is already updated with the same $ip_version address: $my_ip_address."
        return 1
    fi

    return 0
}

delete_hostname() {
    local ip_version="${1:?Missing: IP version}"

    local result=$( curl -s "https://$HOST_NAME:$SECRET_KEY@${ip_version,,}.nsupdate.info/nic/delete" )
    local result_successful="deleted *"
    case "$result" in
        $result_successful)
            log "$ip_version address deleted for $HOST_NAME."
            ;;
        *)
            log "Failed to delete $ip_version address for $HOST_NAME. Error: $result"
            exit 1
            ;;
    esac
}

change_hostname() {
    local ip_version="${1:?Missing: IP version}"

    get_result_code() {
        echo $1 | cut -d ' ' -f 1
    }
    get_result_ip_address() {
        echo $1 | cut -d ' ' -f 2
    }

    local result=$( curl -s "https://$HOST_NAME:$SECRET_KEY@${ip_version,,}.nsupdate.info/nic/update" )
    local updated_ip_address=$( get_result_ip_address "$result" )
    local result_successful_changed="good"
    local result_successful_unchanged="nochg"
    case $( get_result_code "$result" ) in
        $result_successful_changed)
            log "$HOST_NAME has been updated successfully with $ip_version address: $updated_ip_address"
            ;;
        $result_successful_unchanged)
            log "$HOST_NAME still has the same $ip_version address: $updated_ip_address."
            ;;
        *)
            log "Failed to update $HOST_NAME with $ip_version address. Error: $result"
            exit 1
            ;;
    esac
}

update_hostname() {
    local ip_version="${1:?Missing: IP version}"
    local my_ip_address="$2"

    if [[ -z "$my_ip_address" ]]; then
        delete_hostname "$1"
    else
        change_hostname "$1"
    fi
}

get_my_ip_address() {
    local ip_version="${1:?Missing: IP version}"
    curl -s https://${ip_version,,}.nsupdate.info/myip
}

process() {
    local ip_version="${1:?Missing: IP version}"

    local my_ip_address=$( get_my_ip_address "$ip_version" )
    if [[ "${ip_version,,}" == "ipv4" ]] && is_under_CGN "$my_ip_address"; then
        my_ip_address=""
    fi

    if is_update_needed "$ip_version" "$my_ip_address"; then
        update_hostname "$ip_version" "$my_ip_address"
    fi
}

process "IPv4"
process "IPv6"

exit 0