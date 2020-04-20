#!/bin/sh
brctl addbr packet
ip addr add 192.168.2.1/24 dev packet
ip link  set up dev packet
echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables
sysctl -w .net.ipv4.conf.packet.bc_forwarding=1
sysctl -w net.ipv4.ip_forward=1

