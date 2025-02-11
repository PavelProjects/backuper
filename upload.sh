#!/bin/bash

CONFIG_DIR="/home/pobopo/projects/backuper"
NAS_DIR="/mnt/main/storage/backups"
NAS_ADDRESS="admin@192.168.1.6"
TMP_DIR="/tmp/backups"
CHECKSUMS_DIR="checksums"
XARGS_PROCESSES=10

RC="\033[1;31m"
OC="\033[0;33m"
GC="\033[0;32m"
GCB="\033[1;32m"
NC="\033[0m"

function log {
  args=-e
  if [[ $2 == "-n" ]]; then
    args=-en
  fi
  echo $args "\033[2;36m[$(date '+%d.%m.%y %H:%M:%S')]\033[0m $1"
}

if [[ ! -f $1 ]]; then
  echo -e $RC"Bad targets target: $1"$NC
  exit 1
fi

mkdir -p $CONFIG_DIR
mkdir -p $TMP_DIR

BACKUPS_DIR=$(date '+%d_%m_%y')

log $GC"Server address: $NAS_ADDRESS, folder: $NAS_DIR, backups folder: $BACKUPS_DIR, checksums folder: $CHECKSUMS_DIR"$NC
BACKUPS_DIR="$NAS_DIR/$BACKUPS_DIR"
CHECKSUMS_DIR="$NAS_DIR/$CHECKSUMS_DIR"

ssh -n $NAS_ADDRESS "mkdir -p $BACKUPS_DIR && mkdir -p $CHECKSUMS_DIR"
if [[ $? -ne 0 ]]; then
  log $RC"Failed to create folder $NAS_DIR on $NAS_ADDRESS"$NC
  exit 1
fi

TOTAL=$(wc -l < $1)
COUNTER=0
while IFS= read -r target; do
  ((COUNTER++))
  log $GCB"[$COUNTER/$TOTAL] Processing $target"$NC

  name=$(basename $target)
  checksum_file=$CHECKSUMS_DIR/$name.sha256

  log "\tCaltulating checksum"
  current_checksum=$(find $target -type f | xargs -P $XARGS_PROCESSES -I {} "sha256sum" "{}" | sort | sha256sum | awk '{print $1}')
  remote_checksum=$(ssh -n $NAS_ADDRESS "cat $checksum_file 2>/dev/null")

  if [[ $current_checksum == $remote_checksum ]]; then
    log $OC"\tChecksums matches, skipping upload"$NC
    continue
  fi

  compressed=false
  if [[ -d $target ]]; then
      compressed=true
      file_to_upload="$TMP_DIR/$name.tar.gz"

      if [[ -f $file_to_upload ]]; then
        log "\tArchive $file_to_upload already exists, skipping compression"
      else
        log "\tCompressing directory to $file_to_upload.." -n
        tar -c --use-compress-program=pigz -f $file_to_upload -C $(dirname $target) $name --checkpoint=.10000
        
        if [[ $? -ne 0 ]]; then
          log $RC"Failed to compress folder $target"$NC
          exit 1
        fi

        echo " Done"
      fi
  elif [[ -f $target ]]; then
      file_to_upload=$target
  else
      log $RC"Path $target is not valid"$NC
      exit 1
  fi

  log "\tTransfering data (file size $(du -h $file_to_upload | awk '{print $1}'))"

  # todo better style for progress
  rsync --info=progress2 --info=name0 --ignore-existing  $file_to_upload $NAS_ADDRESS:$BACKUPS_DIR
  ssh -n $NAS_ADDRESS "echo $current_checksum > $checksum_file"

  if [[ $? -ne 0 ]]; then
    log $RC"Failed to transfer data"$NC
    exit 1
  fi

  if [[ "$compressed" == "true" ]]; then
      rm $file_to_upload
  fi

  log $GC"\tDone"$NC
done < $1

log $GCB"Backup finished!"$NC
