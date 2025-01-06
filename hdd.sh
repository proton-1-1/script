#!/bin/bash

# -----------------------------------------------
# MIT License
#
# Author: 147611@proton.me
# Copyright (c) 2025 proton-1-1 
# https://github.com/proton-1-1/script
# ver: 1.0
# -----------


set -o allexport
source "$HOME/.env"
set +o allexport

send_to_discord() {
    local message="$1"
    
    curl -X POST -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    "$DISCORD_WEBHOOK_URL"
    
    if [ $? -eq 0 ]; then
        echo "Message sent to Discord"
    else
        echo "Failed to send message to Discord"
    fi
}

log_to_db() {
    local hostname="$1"
    local mount_point="$2"
    local filesystem="$3"
    local total_space="$4"
    local used_space="$5"
    local available_space="$6"
    local usage_percent="$7"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    exists=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se \
    "SELECT COUNT(*) FROM disk_usage WHERE hostname='$hostname' AND mount_point='$mount_point' AND filesystem='$filesystem';")

    if [ "$exists" -gt 0 ]; then
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
        "UPDATE disk_usage SET total_space='$total_space', used_space='$used_space', available_space='$available_space', usage_percent='$usage_percent', timestamp='$timestamp' WHERE hostname='$hostname' AND mount_point='$mount_point' AND filesystem='$filesystem';"
    else
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
        "INSERT INTO disk_usage (hostname, mount_point, filesystem, total_space, used_space, available_space, usage_percent, timestamp) \
        VALUES ('$hostname', '$mount_point', '$filesystem', '$total_space', '$used_space', '$available_space', '$usage_percent', '$timestamp');"
    fi
}

log_pv_to_db() {
    local hostname="$1"
    local pv_name="$2"
    local vg_name="$3"
    local pv_size="$4"
    local pv_free="$5"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    exists=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se \
    "SELECT COUNT(*) FROM pv_usage WHERE hostname='$hostname' AND pv_name='$pv_name';")

    if [ "$exists" -gt 0 ]; then
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
        "UPDATE pv_usage SET pv_size='$pv_size', pv_free='$pv_free', timestamp='$timestamp' WHERE hostname='$hostname' AND pv_name='$pv_name';"
    else
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
        "INSERT INTO pv_usage (hostname, pv_name, vg_name, pv_size, pv_free, timestamp) \
        VALUES ('$hostname', '$pv_name', '$vg_name', '$pv_size', '$pv_free', '$timestamp');"
    fi
}

get_hosts_from_db() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
    "SELECT hostname FROM hosts WHERE status = 1;" | tail -n +2 > hosts_list.txt
    
    mapfile -t HOSTS < hosts_list.txt
    rm -f hosts_list.txt
}

get_hosts_from_db

get_pv_info() {
    local host="$1"
    
    pv_output=$(ssh "$host" "sudo pvs --noheadings -o pv_name,vg_name,pv_size,pv_free")
    if [ $? -ne 0 ]; then
        echo "Błąd podczas łączenia się z hostem $host. Pomijam go."
        return
    fi

    while read -r pv_name vg_name pv_size pv_free; do
        log_pv_to_db "$host" "$pv_name" "$vg_name" "$pv_size" "$pv_free"
    done <<< "$pv_output"
}

get_disk_resources_from_db() {
    local hostname="$1"
    
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
    "SELECT mount_point, filesystem FROM disk_usage WHERE hostname='$hostname';" | tail -n +2 > disk_resources.txt
    
    mapfile -t disk_resources < disk_resources.txt
    rm -f disk_resources.txt
}

for host in "${HOSTS[@]}"; do
    echo "Pobieranie danych z hosta $host..."

    df_output=$(ssh "$host" "sudo df -h --output=source,target,size,used,avail,pcent")
    if [ $? -ne 0 ]; then
        echo "Błąd podczas łączenia się z hostem $host. Pomijam go."
        continue
    fi

    while read -r filesystem mount_point total_space used_space available_space usage_percent; do
        usage_percent="${usage_percent//%/}"
        log_to_db "$host" "$mount_point" "$filesystem" "$total_space" "$used_space" "$available_space" "$usage_percent"
        
        if [[ "$filesystem" == /dev/mapper* ]] && [ "$usage_percent" -gt "$THRESHOLD" ]; then
            MESSAGE="Alert: Przestrzeń dyskowa na hoście $host, system plików $filesystem ($mount_point) przekroczyła próg $THRESHOLD% ($usage_percent%)"
            send_to_discord "$MESSAGE"
        fi
    done <<< "$(echo "$df_output" | tail -n +2)"

    get_pv_info "$host"
    get_disk_resources_from_db "$host"

    for resource in "${disk_resources[@]}"; do
        mount_point=$(echo "$resource" | awk '{print $1}')
        filesystem=$(echo "$resource" | awk '{print $2}')

        ssh "$host" "sudo df -h | grep -w '$mount_point'" &> /dev/null
        if [ $? -ne 0 ]; then
            echo "Zasób $mount_point ($filesystem) nie istnieje na serwerze $host. Usuwam go z bazy danych."
            mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
            "DELETE FROM disk_usage WHERE hostname='$host' AND mount_point='$mount_point' AND filesystem='$filesystem';"
            if [ $? -eq 0 ]; then
                echo "Usunięto nieistniejący zasób: $host, $mount_point, $filesystem"
            else
                echo "Błąd podczas usuwania zasobu: $host, $mount_point, $filesystem"
            fi
        fi
    done
done
