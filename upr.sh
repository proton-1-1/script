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
    echo "Błąd: Plik .env nie został znaleziony pod ścieżką $ENV_FILE."
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
        echo "Nie masz uprawnień do uruchomienia komendy '$command' na hoście $host."
        MESSAGE="Nie masz uprawnień do uruchomienia komendy '$command' na hoście $host."
        send_to_discord "$MESSAGE"
        return 1
    fi
}

check_ssh_login() {
    local host=$1

    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=QUIET -q "$host" exit; then
        echo "Brak dostępu do hosta $host (SSH nie działa lub brak uprawnień)."
        MESSAGE="Brak dostępu do hosta $host (SSH nie działa lub brak uprawnień)."
        send_to_discord "$MESSAGE"
        return 1  
    fi
}

check_service_status() {
    local host=$1

    service_exists=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o LogLevel=QUIET "$host" "systemctl list-units --all --type=service | grep -w 'check_start.service'")

    if [ -z "$service_exists" ]; then
        echo "Usługa check_start.service na hoście $host nie jest zainstalowana."
        MESSAGE="Usługa check_start.service na hoście $host nie jest zainstalowana."
        send_to_discord "$MESSAGE"
    else
        echo "Usługa check_start.service na hoście $host jest zainstalowana, Super!!!!!."
    fi
}

echo "Pobieram listę hostów z bazy danych..."
hosts=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT hostname FROM hosts WHERE status = 1;" -s -N)

if [ -z "$hosts" ]; then
    echo "Brak hostów w bazie danych."
    exit 1
fi

echo "Sprawdzam logowanie do hostów..."
for host in $hosts; do
    if check_ssh_login "$host"; then
        check_service_status "$host"

        for command in "${commands[@]}"; do
            check_permissions "$host" "$command"
        done
    fi
done
