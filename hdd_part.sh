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

get_partitions() {
    local hostname=$1  

    partitions=$(ssh "$hostname" "sudo mount -v | awk '{print \$1, \$3, \$5}'")

    if [ $? -ne 0 ]; then
        echo "SSH connection error with host $hostname"
        return 1
    fi

    echo "$partitions" | while read -r line; do
        if [[ $line =~ ^Filesystem ]]; then
            continue
        fi

        filesystem=$(echo "$line" | awk '{print $1}' | xargs)  
        mount_point=$(echo "$line" | awk '{print $2}' | xargs) 
        fs_type=$(echo "$line" | awk '{print $3}' | xargs)  

        if [[ $filesystem =~ ^/dev/mapper ]]; then
            existing_partition=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
                SELECT COUNT(*) FROM partitions WHERE host = '$hostname' AND filesystem = '$filesystem';
            ")

            if [ "$existing_partition" -eq 0 ]; then
                echo "Found a new partition: $filesystem" 
                server_partition=$filesystem  

                echo "Adding partition $server_partition to the database for host $hostname"
                mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
                    INSERT INTO partitions (host, filesystem, mount_point, fs_type)
                    VALUES ('$hostname', '$server_partition', '$mount_point', '$fs_type');
                "
                echo "Partition ($server_partition) has been added to the database."
            else
                echo "Partition $filesystem already exists in the database. Skipping addition."
            fi
        fi
    done   
}

remove_nonexistent_hosts() {
    disabled_hosts=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT hostname FROM hosts WHERE status = 0;")

    for disabled_host in $disabled_hosts; do
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
            DELETE FROM partitions WHERE host = '$disabled_host';
        "
    done
}

remove_nonexistent_partitions() {
    host_data=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT hostname FROM hosts WHERE status = 1;")

    for hostname in $host_data; do
        echo "Checking partitions on host $hostname..."

        disk_resources=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "
            SELECT mount_point, filesystem FROM partitions WHERE host = '$hostname';
        ")

        partition_array=()
        while read -r resource; do
            partition_array+=("$resource")
        done <<< "$disk_resources"

        for resource in "${partition_array[@]}"; do
            mount_point=$(echo "$resource" | awk '{print $1}')
            filesystem=$(echo "$resource" | awk '{print $2}')

            ssh "$hostname" "sudo df -h | grep -w '$mount_point'" &> /dev/null

            if [ $? -ne 0 ]; then
                echo "Partition $mount_point ($filesystem) does not exist on host $hostname. Removing it from the database."
                mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
                    DELETE FROM partitions WHERE host = '$hostname' AND mount_point = '$mount_point' AND filesystem = '$filesystem';
                "
                echo "Removed partition $mount_point ($filesystem) from the database."
            fi
        done
    done
}

host_data=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT hostname FROM hosts WHERE status = 1;")

IFS=$'\n'
for hostname in $host_data; do
    echo "Fetching data from host $hostname..."
    get_partitions "$hostname"
done

remove_nonexistent_partitions
remove_nonexistent_hosts

echo "Script completed."
