#!/bin/bash

set -e

: ${DATABASE:?"DATABASE env variable is required"}
export BACKUP_PATH=${BACKUP_PATH:-/data/influxdb/backup}
export BACKUP_ARCHIVE_PATH=${BACKUP_ARCHIVE_PATH:-${BACKUP_PATH}.tgz}
export DATABASE_HOST=${DATABASE_HOST:-localhost}
export DATABASE_PORT=${DATABASE_PORT:-8088}
export DATABASE_META_DIR=${DATABASE_META_DIR:-/var/lib/influxdb/meta}
export DATABASE_DATA_DIR=${DATABASE_DATA_DIR:-/var/lib/influxdb/data}

# Add this script to the crontab and start crond
cron() {
  echo "$(date '+%d/%m/%Y %H:%M:%S') Starting backup cron job with frequency '$1'"
  echo "$1 $0 backup >> /dev/stdout 2>&1" > /var/spool/cron/crontabs/root
  crontab /var/spool/cron/crontabs/root
  crond -f
}

# Dump the database to a file and push it to S3
backup() {
  # Initialise the timeframe for backup
  START_TIME=$(TZ=:Singapore date --date="1 days ago" -u +"%Y-%m-%dT00:00:00Z")
  END_TIME=$(TZ=:Singapore date -u +"%Y-%m-%dT00:00:00Z")
  FILE_NAME=$(TZ=:Singapore date --date="1 days ago" -u +"%Y-%m-%d")

  # Dump database to directory
  echo "$(date '+%d/%m/%Y %H:%M:%S') Backing up $DATABASE to $BACKUP_PATH for date $FILE_NAME"
  echo "$(date '+%d/%m/%Y %H:%M:%S') Shard: $START_TIME to $END_TIME"
  if [ -d $BACKUP_PATH ]; then
    rm -rf $BACKUP_PATH
  fi
  mkdir -p $BACKUP_PATH
  influxd backup -database $DATABASE -host $DATABASE_HOST:$DATABASE_PORT -start $START_TIME -end $END_TIME $BACKUP_PATH
  if [ $? -ne 0 ]; then
    echo "$(date '+%d/%m/%Y %H:%M:%S') Failed to backup $DATABASE to $BACKUP_PATH"
    exit 1
  fi

  # Compress backup directory
  if [ -e $BACKUP_ARCHIVE_PATH ]; then
    rm -rf $BACKUP_ARCHIVE_PATH
  fi
  tar -cvzf $BACKUP_ARCHIVE_PATH $BACKUP_PATH

  if aws s3 cp $BACKUP_ARCHIVE_PATH s3://${S3_BUCKET}/${FILE_NAME}.tgz; then
    echo "$(date '+%d/%m/%Y %H:%M:%S') Backup file copied to s3://${S3_BUCKET}/${FILE_NAME}.tgz"
  else
    echo "$(date '+%d/%m/%Y %H:%M:%S') Backup file failed to upload"
    exit 1
  fi

  # Cleanup backups from disk
  rm $BACKUP_ARCHIVE_PATH
  rm -rf $BACKUP_PATH

  echo "$(date '+%d/%m/%Y %H:%M:%S') Completed backup"
}

# Handle command line arguments
case "$1" in
  "cron")
    cron "$2"
    ;;
  "backup")
    backup
    ;;
  *)
    echo "Invalid command '$@'"
    echo "Usage: $0 {backup|cron <pattern>}"
esac
