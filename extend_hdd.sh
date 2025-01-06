#!/bin/bash

# -----------------------------------------------
# MIT License
#
# Author: 147611@proton.me
# Copyright (c) 2025 proton-1-1 
# https://github.com/proton-1-1/script
# ver: 1.0
# -----------

ENV_FILE="$HOME/.env"

if [[ -f "$ENV_FILE" ]]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Error: The .env file was not found at the path $ENV_FILE."
    exit 1
fi

get_partitions_from_db() {
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
    "SELECT host, filesystem, mount_point, expand_size, fs_type FROM partitions WHERE status = 1;" > partitions_list.txt

    sed -i '1d' partitions_list.txt  
    mapfile -t PARTITIONS < partitions_list.txt
    rm -f partitions_list.txt
}

extend_space() {
    local host="$1"
    local filesystem="$2"
    local expand_size="$3"  
    local fs_type="$4"      

    echo "Usage on $filesystem has exceeded the threshold of $THRESHOLD%. Increasing space by ${expand_size}GB."

    ssh "$host" "sudo lvextend -L +${expand_size}G $filesystem"

    if [[ "$fs_type" == "xfs" ]]; then
        ssh "$host" "sudo xfs_growfs $filesystem"
        echo "Space on $filesystem (XFS) has been increased by ${expand_size}GB."
    else
        ssh "$host" "sudo resize2fs $filesystem"
        echo "Space on $filesystem (ext3/ext4) has been increased by ${expand_size}GB."
    fi
}

get_partitions_from_db

for partition in "${PARTITIONS[@]}"; do
    IFS=' ' read -r host filesystem mount_point expand_size fs_type <<< "$(echo "$partition" | awk '{$1=$1; print}')"

    if [[ -z "$host" || -z "$filesystem" || -z "$mount_point" || -z "$expand_size" || -z "$fs_type" ]]; then
        echo "Error: Invalid data: $partition"
        continue
    fi

    echo "Retrieving data from host $host..."
    
    usage_percent=$(ssh "$host" "df --output=pcent $filesystem | tail -n 1 | tr -d '[:space:]%'")

    echo "df result for $filesystem on host $host: $usage_percent%"

    if ! [[ "$usage_percent" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid df result for $filesystem on host $host"
        continue
    fi

    echo "Usage on $filesystem is $usage_percent%."

    if [ "$usage_percent" -gt "$THRESHOLD" ]; then
        MESSAGE="Disk resize: Disk space on host $host, filesystem $filesystem ($mount_point) has exceeded the threshold of $THRESHOLD% ($usage_percent%) and has been increased."
        curl -X POST -H "Content-Type: application/json" \
        -d "{\"content\": \"$MESSAGE\"}" \
        "$DISCORD_WEBHOOK_URL"
        
        extend_space "$host" "$filesystem" "$expand_size" "$fs_type"
    else
        echo "Usage on $filesystem is below the threshold of $THRESHOLD%."
    fi
done
