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

output_file="/var/www/html/partitions_to_extend.html"

echo "<!DOCTYPE html>" > "$output_file"
echo "<html lang=\"en\">" >> "$output_file"
echo "<head>" >> "$output_file"
echo "<meta charset=\"UTF-8\">" >> "$output_file"
echo "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">" >> "$output_file"
echo "<title>Partition Expansion Report</title>" >> "$output_file"
echo "<style>" >> "$output_file"
echo "body { font-family: Arial, sans-serif; line-height: 1.6; margin: 20px; background-color: #f4f4f4; }" >> "$output_file"
echo "table { width: 100%; margin-top: 20px; border-collapse: collapse; }" >> "$output_file"
echo "th, td { padding: 8px; text-align: left; border: 1px solid #ddd; }" >> "$output_file"
echo "th { background-color: #4CAF50; color: white; }" >> "$output_file"
echo "tr:nth-child(even) { background-color: #f2f2f2; }" >> "$output_file"
echo "</style>" >> "$output_file"
echo "</head>" >> "$output_file"
echo "<body>" >> "$output_file"

echo "<h1>Partition Expansion Report</h1>" >> "$output_file"
echo "<p>Report generated on: $(date)</p>" >> "$output_file"

echo "<h2>Partitions to be Extended</h2>" >> "$output_file"
echo "<table>" >> "$output_file"
echo "<tr><th>Host</th><th>Filesystem</th><th>Mount Point</th><th>Size to Increase (GB)</th><th>Status</th><th>FS Type</th></tr>" >> "$output_file"

partitions_data=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -se "SELECT host, filesystem, mount_point, expand_size, status, fs_type FROM partitions WHERE expand_size IS NOT NULL ORDER BY host;")

if [[ -n "$partitions_data" ]]; then
  while IFS=$'\t' read -r host filesystem mount_point size_to_increase status fs_type; do
    #
    if [[ "$status" -eq 0 ]]; then
      status_text="OFF"
      status_color="color: red;"
    elif [[ "$status" -eq 1 ]]; then
      status_text="ON"
      status_color="color: green;"
    else
      status_text="Unknown"
      status_color="color: gray;"
    fi
    
    echo "<tr><td>$host</td><td>$filesystem</td><td>$mount_point</td><td>$size_to_increase</td><td style=\"$status_color\">$status_text</td><td>$fs_type</td></tr>" >> "$output_file"
  done <<< "$partitions_data"
else
  echo "<tr><td colspan=\"6\">No partitions to extend</td></tr>" >> "$output_file"
fi

echo "</table>" >> "$output_file"
echo "</body>" >> "$output_file"
echo "</html>" >> "$output_file"

echo "HTML report has been generated: $output_file"
