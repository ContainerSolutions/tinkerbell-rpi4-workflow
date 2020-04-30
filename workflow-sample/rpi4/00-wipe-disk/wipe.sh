#!/bin/bash

if lsblk -p |grep -q mmc
then
  echo "SD card present, proceeding with erasing MBR"
  disk=$(lsblk -dno name -e1,7,11 | sed 's|^|/dev/|' | sort)
  if dd if=/dev/zero of=$disk bs=1M count=1
  then
    echo "Successfully erased MBR"
    exit 0
  else
    echo "Something went wrong while erasing MBR"
    exit 1
  fi
else
  echo "SD card not present"
  exit 1
fi
