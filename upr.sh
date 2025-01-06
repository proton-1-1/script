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
    echo "Error: The .env file was not found at path $ENV_FILE."
    exit 1
fi

WEBHOOK_URL="$DISCORD_WEBHOOK_URL"

send_to_discord() {
    local message="$1"
    
    curl -X POST -H "Content-Type: application/json" \
    -d "{\"content\": \"$message\"}" \
    "$WEBHOOK_URL"
    
    if [ $? -eq 0 ]; then
        echo "Message sent to Discord"
    else
        echo "Failed to send message to Discord"
    fi

    sleep 1
}

commands=("df" "pvs" "lvextend" "resize2fs" "xfs_growfs" "mount")

check_permissions() {
    local host=$1
    local command=$2

    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=QUIET "$host" "sudo -l | grep -q '$command'"; then
        echo "You do not have permission to run the command '$command' on host $host."
        MESSAGE="You do not have permission to run the command '$command' on host $host."
        send_to_discord "$MESSAGE"
        return 1
    fi
}

check_ssh_login() {
    local host=$1

    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=QUIET -q "$host" exit; then
        echo "No access to host $host (SSH is down or permissions are missing)."
        MESSAGE="No access to host $host (SSH is down or permissions are missing)."
        send_to_discord "$MESSAGE"
        return 1  
    fi
}

check_service_status() {
    local host=$1

    service_exists=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=QUIET "$host" "systemctl list-units --all --type=service | grep -w 'check_start.service'")

    if [ -z "$service_exists" ]; then
        echo "The service check_start.service is not installed on host $host."
        MESSAGE="The service check_start.service is not installed on host $host."
        send_to_discord "$MESSAGE"
    else
        echo "The service check_start.service is installed on host $host. Great!"
    fi
}

echo "Fetching the list of hosts from the database..."
hosts=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT hostname FROM hosts WHERE status = 1;" -s -N)

if [ -z "$hosts" ]; then
    echo "No hosts in the database."
    exit 1
fi

echo "Checking SSH login to hosts..."
for host in $hosts; do
    if check_ssh_login "$host"; then
        check_service_status "$host"

        for command in "${commands[@]}"; do
            check_permissions "$host" "$command"
        done
    fi
done
