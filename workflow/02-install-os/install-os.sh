#!/bin/bash
set -e

osurl=${OS_URL:-https://downloads.raspberrypi.org/raspbian_lite_latest}

echo "Downloading os from ${osurl}"

code=$(curl -o os.zip -L -w %{http_code} ${osurl})

if [[ "${code}" -eq "200" ]]
then
  disk=$(lsblk -dno name -e1,7,11 | sed 's|^|/dev/|' | sort)
  echo "Successfully downloaded os, proceeding with its installation to ${disk}"
  unzip -p os.zip | dd of=${disk} status=progress
  echo "Installed OS successfully. Refreshing partition table."
  partx -u ${disk} 
else
  echo "Failed to download OS, http code: ${code} different than 200"
  exit 1
fi
