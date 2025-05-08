#!/bin/bash
# ENV SETUP
export PATH=$PATH:/usr/local/bin  # <-- Add this if mydumper is here
MYDUMPER_PATH=$(command -v mydumper)  # dynamically find mydumper

CONFIG_DB_HOST="x.x.x.x"
CONFIG_DB_NAME="config_db"
CONFIG_DB_USER="x.x.x.x"
CONFIG_DB_PASS="x.x.x.x"
BACKUP_SUBDIR=$(date +"%Y-%m-%d_%H-%M")

# Log to database
log_to_db() {
    local status="$1"
    local message="$2"
    mysql -h "$CONFIG_DB_HOST" -u"$CONFIG_DB_USER" -p"$CONFIG_DB_PASS" --default-character-set=utf8mb4 \
        -e "INSERT INTO $CONFIG_DB_NAME.backup_logs (database_name, status, message) VALUES ('ALL_DATABASES', '${status}', '${message}');"
}

# Get current time
CURRENT_HOUR=$(date +"%H")
CURRENT_MINUTE=$(date +"%M")

# Check if it's a scheduled backup time
IS_SCHEDULED=$(mysql -N -B -h "$CONFIG_DB_HOST" -u"$CONFIG_DB_USER" -p"$CONFIG_DB_PASS" \
    -e "SELECT COUNT(*) FROM $CONFIG_DB_NAME.server_backup_schedule WHERE run_hour = $CURRENT_HOUR AND run_minute = $CURRENT_MINUTE;")

if [ "$IS_SCHEDULED" -eq 0 ]; then
    exit 0
fi

# Fetch DB credentials
read -r DB_HOST DB_USER DB_PASS BACKUP_BASE_PATH <<< $(mysql -N -B -h "$CONFIG_DB_HOST" -u"$CONFIG_DB_USER" -p"$CONFIG_DB_PASS" \
    -e "SELECT db_host, db_user, db_password, backup_path FROM $CONFIG_DB_NAME.db_credentials LIMIT 1;")

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$BACKUP_BASE_PATH" ]; then
    log_to_db "ERROR" "Missing required data in db_credentials (host, user, hasło, ścieżka)"
    exit 1
fi

BACKUP_DIR="$BACKUP_BASE_PATH/$BACKUP_SUBDIR"
mkdir -p "$BACKUP_DIR"

# Perform backup
log_to_db "START" "Starting full server backup to $BACKUP_DIR"

if "$MYDUMPER_PATH" -h "$DB_HOST" -u "$DB_USER" -p "$DB_PASS" --threads=4 -o "$BACKUP_DIR"; then
    log_to_db "END" "Backup completed successfully."
else
    log_to_db "ERROR" "Error during backup to $BACKUP_DIR"
fi

