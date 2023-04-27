#!/bin/bash

while [[ "$1" =~ ^- ]]; do case $1 in
  -w | --wireguard )
    is_wireguard_flag=1
    shift
    ;;
  -I | --interface )
    shift
    interface="$1"
    shift
    ;;
  -p | --peer )
    shift
    peer_ip_address="$1"
    shift
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
esac; done

[ -n "$1" ] && echo "Unexpected arguments: $1" && exit 1

[ ${interface:?Missing: Interface name} ]
[ ${peer_ip_address:?Missing: Peer IP address} ]

function is_peer_alive() {
    ping -c 1 -W 1 -q -I $interface $peer_ip_address &> /dev/null
}
exit 0
function is_wireguard() {
    [ -n "$is_wireguard_flag" ] && command -v wg-quick &> /dev/null
}

is_peer_alive || \
if is_wireguard ; then
    wg-quick down $interface
    wg-quick up $interface
else
    ifup $interface
fi
