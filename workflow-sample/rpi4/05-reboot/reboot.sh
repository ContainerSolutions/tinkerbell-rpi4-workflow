#!/bin/sh 
echo "Scheduling reboot"

if [[ -z $REGISTRY ]]
then
  echo "REGISTRY not defined" && exit 1
fi
docker run --detach --privileged $REGISTRY/base sh -c "sleep 30 && echo 1 > /proc/sys/kernel/sysrq && echo b > /proc/sysrq-trigger"
echo "Reboot scheduled in 30s" 
