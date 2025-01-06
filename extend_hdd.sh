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

    echo "Wykorzystanie przestrzeni na $filesystem przekroczyło próg $THRESHOLD%. Zwiększam przestrzeń o ${expand_size}GB."

    ssh "$host" "sudo lvextend -L +${expand_size}G $filesystem"

    if [[ "$fs_type" == "xfs" ]]; then
        ssh "$host" "sudo xfs_growfs $filesystem"
        echo "Przestrzeń na $filesystem (XFS) została zwiększona o ${expand_size}GB."
    else
        ssh "$host" "sudo resize2fs $filesystem"
        echo "Przestrzeń na $filesystem (ext3/ext4) została zwiększona o ${expand_size}GB."
    fi
}

get_partitions_from_db

for partition in "${PARTITIONS[@]}"; do
    IFS=' ' read -r host filesystem mount_point expand_size fs_type <<< "$(echo "$partition" | awk '{$1=$1; print}')"

    if [[ -z "$host" || -z "$filesystem" || -z "$mount_point" || -z "$expand_size" || -z "$fs_type" ]]; then
        echo "Błąd: Niepoprawne dane: $partition"
        continue
    fi

    echo "Pobieranie danych z hosta $host..."
    
    usage_percent=$(ssh "$host" "df --output=pcent $filesystem | tail -n 1 | tr -d '[:space:]%'")

    echo "Wynik df dla $filesystem na hoście $host: $usage_percent%"

    if ! [[ "$usage_percent" =~ ^[0-9]+$ ]]; then
        echo "Błąd: Niepoprawny wynik df dla $filesystem na hoście $host"
        continue
    fi

    echo "Wykorzystanie przestrzeni na $filesystem wynosi $usage_percent%."

    if [ "$usage_percent" -gt "$THRESHOLD" ]; then
        MESSAGE="Zmiana wielkości dysku: Przestrzeń dyskowa na hoście $host, system plików $filesystem ($mount_point) przekroczyła próg $THRESHOLD% ($usage_percent%) i została zwiększona."
        curl -X POST -H "Content-Type: application/json" \
        -d "{\"content\": \"$MESSAGE\"}" \
        "$DISCORD_WEBHOOK_URL"
        
        extend_space "$host" "$filesystem" "$expand_size" "$fs_type"
    else
        echo "Wykorzystanie przestrzeni na $filesystem jest poniżej progu $THRESHOLD%."
    fi
done
