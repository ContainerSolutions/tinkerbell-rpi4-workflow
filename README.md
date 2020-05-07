# Configuring Kubernetes cluster using tinkerbell

This repository contains an example tinkerbell (https://tinkerbell.org/) workflow for provisioning k8s control plane and
worker nodes on top of the raspberries pi version 4 (rpi4). 

## Introduction:

Tinkerbell is engine for provisioning bare metal servers, it helps users to build fully bootable and
operational machine from scratch. It can be used for any type of the machine from traditional 
x86_64 servers to arm based single boards computers. This repository contains step by step instruction, how 
leverage tinkerbell provisoning engine to build fully operational k8s cluster.

## Preparation:
### Setting local environment
In order to install tinkerbell locally we need to setup a virtual machine or a dedicated bare metal server. 
In the presented example the following setup was created: 

![Alt text](img/tinkerbell-lab.png "lab design")

The lab consist of:
1) KVM+QEMU hypervisor running on top of fedora 31
1) Centos 7 virtual machine hosting tinkerbell provisioner
1) Raspberries Pies version 4 workers

#### Configuring hypervisor network
In order to ensure flawless communication between rpi4 - host- vm, it is required to first setup a bridge 
in the host. In the fedora31 it can be achieved as follows: 
```bash
sudo nmcli con add ifname packet type bridge con-name packet
sudo ip addr add <ip addr> dev packet
sudo ip link  set up dev packet
sudo nmcli con add type bridge-slave ifname <hv lan interface> master packet
sudo sysctl -w .net.ipv4.conf.packet.bc_forwarding=1
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=0
```
**Note:** Adjust the above configuration to your host. The listed kernel parameters are used to allow forwarding of dhcp
request to virtual machine.

### Creating virtual machine
Ensure virtual machine is connected to the previously created bridge and it does not block traffic for http, https, dhcp and tftp. 

### Installing tinkerbell
Connect to the virtual machine and follow steps from https://tinkerbell.org/setup/prep_provisioner/

### Configure raspberry pi