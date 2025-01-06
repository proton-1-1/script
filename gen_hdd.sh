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

OUTPUT_FILE="/var/www/html/disk_usage_report.html"

GREEN_THRESHOLD=${GREEN_THRESHOLD:-60}
YELLOW_THRESHOLD=${YELLOW_THRESHOLD:-75}
RED_THRESHOLD=${RED_THRESHOLD:-90}

generate_html_table_for_host() {
    local HOSTNAME="$1"
    
    echo "<h2>Raport przestrzeni dyskowej dla hosta $HOSTNAME</h2>"
    
    HOST_STATUS=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -se \
    "SELECT status FROM hosts WHERE hostname='$HOSTNAME';")
    
    if [ "$HOST_STATUS" == "1" ]; then
        echo "<p>Monitorowany: <span style='color:green;'><b>ON</b></span></p>"
    elif [ "$HOST_STATUS" == "0" ]; then
        echo "<p>Monitorowany: <span style='color:red;'><b>OFF</b></span></p>"
    else
        echo "<p>Monitorowanie: <span style='color:gray;'><b>Brak informacji</b></span></p>"
    fi

    echo "<table border='1' cellspacing='0' cellpadding='5'>"
    echo "<thead><tr><th>System plików</th><th>Mount Point</th><th>Całkowita przestrzeń</th><th>Użyta przestrzeń</th><th>Dostępna przestrzeń</th><th>Procent użycia</th></tr></thead>"
    echo "<tbody>"

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
    "SELECT filesystem, mount_point, total_space, used_space, available_space, usage_percent \
    FROM disk_usage WHERE hostname='$HOSTNAME';" | tail -n +2 | while read filesystem mount_point total_space used_space available_space usage_percent
    do
        
        if [ "$usage_percent" -lt "$GREEN_THRESHOLD" ]; then
            color="green"
        elif [ "$usage_percent" -lt "$YELLOW_THRESHOLD" ]; then
            color="#FFA500"  
        else
            color="red"
        fi

        echo "<tr>"
        echo "<td>$filesystem</td>"
        echo "<td>$mount_point</td>"
        echo "<td>$total_space</td>"
        echo "<td>$used_space</td>"
        echo "<td>$available_space</td>"
        echo "<td style='color:$color;'>$usage_percent%</td>"
        echo "</tr>"
    done

    echo "</tbody>"
    echo "</table>"

    echo "<h2>Raport danych PV dla hosta $HOSTNAME</h2>"
    echo "<table border='1' cellspacing='0' cellpadding='5'>"
    echo "<thead><tr><th>Nazwa PV</th><th>Nazwa VG</th><th>Całkowity rozmiar</th><th>Wolny rozmiar</th></tr></thead>"
    echo "<tbody>"

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
    "SELECT pv_name, vg_name, pv_size, pv_free \
    FROM pv_usage WHERE hostname='$HOSTNAME';" | tail -n +2 | while read pv_name vg_name pv_size pv_free
    do
        
        echo "<tr>"
        echo "<td>$pv_name</td>"
        echo "<td>$vg_name</td>"
        echo "<td>$pv_size</td>"
        echo "<td>$pv_free</td>"
        echo "</tr>"
    done

    echo "</tbody>"
    echo "</table>"

    echo "<p><a href='#top'>Powrót do góry</a></p>"
}

HOSTS=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
"SELECT DISTINCT hostname, description, status FROM hosts;" | tail -n +2)

echo "<html>" > "$OUTPUT_FILE"
echo "<head><title>Raport przestrzeni dyskowej</title></head>" >> "$OUTPUT_FILE"
echo "<body>" >> "$OUTPUT_FILE"
echo "<p>Data wygenerowania raportu: $(date '+%Y-%m-%d %H:%M:%S')</p>" >> "$OUTPUT_FILE"

echo "<h2>Lista monitorowanych hostów</h2>" >> "$OUTPUT_FILE"
echo "<table border='1' cellspacing='0' cellpadding='5'>" >> "$OUTPUT_FILE"
echo "<thead><tr><th>Hostname</th><th>Opis</th><th>Status monitorowania</th></tr></thead>" >> "$OUTPUT_FILE"
echo "<tbody>" >> "$OUTPUT_FILE"

while read -r hostname description status; do
    
    if [[ "$status" == "1" ]]; then
        monitor_status="<span style='color:green;'><b>ON</b></span>"
    elif [[ "$status" == "0" ]]; then
        monitor_status="<span style='color:red;'><b>OFF</b></span>"
    else
        monitor_status="Brak danych"
    fi

    echo "<tr><td><a href='#$hostname'>$hostname</a></td><td>$description</td><td>$monitor_status</td></tr>" >> "$OUTPUT_FILE"
done <<< "$HOSTS"

echo "</tbody>" >> "$OUTPUT_FILE"
echo "</table>" >> "$OUTPUT_FILE"

while read -r hostname _; do
    echo "<a name='$hostname'></a>" >> "$OUTPUT_FILE"  
    generate_html_table_for_host "$hostname" >> "$OUTPUT_FILE"
done <<< "$HOSTS"

echo "</body>" >> "$OUTPUT_FILE"
echo "</html>" >> "$OUTPUT_FILE"

echo "Raport HTML został wygenerowany w pliku $OUTPUT_FILE."
