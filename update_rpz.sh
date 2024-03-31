#!/bin/bash

function update_rpz_files() {
    local rpz_action=${1:?Missing: RPZ action type}

    local forked_process_ids=
    function record_forked_process() {
        forked_process_ids="$! $forked_process_ids"
    }
    function wait_till_forked_processes_joined() {
        for id in $forked_process_ids; do
            wait $id
        done
    }

    local RPZ_OPTIMIZER_COMMON_OPTIONS="-a $rpz_action -n users.noreply.github.com -e 23254804+pdsakurai@users.noreply.github.com"
    local RUN_RPZ_OPTIMIZER="python3 $GITHUB_DIR/RaspberryPiTools/rpz_optimizer.py $RPZ_OPTIMIZER_COMMON_OPTIONS"
    local OUTPUT_DIR="$RPZ_DIR/$rpz_action"

    $RUN_RPZ_OPTIMIZER -d "$OUTPUT_DIR/dns_bypass.rpz" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/doh-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/doh-vpn-proxy-bypass-onlydomains.txt" \
        -t "rpz non-wildcard only" -s "https://raw.githubusercontent.com/jpgpi250/piholemanual/master/DOH.rpz" &
    record_forked_process

    $RUN_RPZ_OPTIMIZER -d "$OUTPUT_DIR/family_protection.rpz" \
        -t "host" -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews-only/hosts" \
        -t "host" -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts" \
        -t "host" -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/porn-only/hosts" &
#       -t "domain" -s "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/fake-onlydomains.txt" \
#       -t "domain" -s "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/gambling-onlydomains.txt" \
#       -t "host" -s "https://www.github.developerdan.com/hosts/lists/dating-services-extended.txt"
#       -t "host" -s "https://www.github.developerdan.com/hosts/lists/hate-and-junk-extended.txt"
    record_forked_process

    $RUN_RPZ_OPTIMIZER -d "$OUTPUT_DIR/ads_and_trackers.rpz" \
        -t "host" -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/light-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/popupads-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.amazon-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.apple-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.huawei-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.winoffice-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.tiktok-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.lgwebos-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.vivo-onlydomains.txt" \
        -t "domain as wildcard" -s "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/native.oppo-realme-onlydomains.txt" \
        -t "host" -s "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Extension/GoodbyeAds-Samsung-AdBlock.txt" \
        -t "host" -s "https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Extension/GoodbyeAds-Xiaomi-Extension.txt" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/samsung" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/huawei" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/windows" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/xiaomi" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/apple" \
        -t "domain" -s "https://raw.githubusercontent.com/nextdns/native-tracking-domains/main/domains/alexa" \
        -t "domain" -s "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/native.apple.txt" &
#        -t "domain" -s "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt"
#        -t "host" -s "https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt"
#        -t "host" -s "https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt"
    record_forked_process

    wait_till_forked_processes_joined
}

function are_there_changes() {
    local num_changes=$( cd "$RPZ_DIR"; git diff --name-only | wc -l )
    [[ $num_changes -gt 0 ]] && return 0 || return 1
}

readonly GITHUB_DIR="/mnt/dietpi_userdata/GitHub"
readonly RPZ_DIR="$GITHUB_DIR/response_policy_zones"

cd "$RPZ_DIR"
git fetch --depth 1 origin master
git reset --hard origin/master
#git pull
update_rpz_files "nxdomain"
update_rpz_files "null"
are_there_changes && {
    git commit -a --message "Updated by cron.daily"
    git push
}
