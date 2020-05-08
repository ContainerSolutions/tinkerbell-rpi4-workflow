# Configuring Kubernetes cluster using tinkerbell

This repository contains an example tinkerbell (https://tinkerbell.org/) workflow for provisioning k8s control plane and
worker nodes on top of the raspberries pi version 4 (RPi4). 

## Introduction:

Tinkerbell is engine for provisioning bare metal servers, it helps users to build fully bootable and
operational machine from scratch. It can be used for any type of the machine from traditional 
x86_64 servers to arm based single-board computers. This repository contains step by step instruction, how 
leverage tinkerbell provisoning engine to build fully operational k8s cluster. It is assumed some familiarity 
with tinkerbell concepts in the below instruction. 

## Preparation:
### Setting local environment
In order to install tinkerbell locally we need to setup a virtual machine or a dedicated bare metal server. 
In the presented example the following setup was created: 

![Alt text](img/tinkerbell-lab.png "lab design")

The lab consist of:
1) KVM+QEMU hypervisor running on top of fedora 31
1) Centos 7 virtual machine hosting tinkerbell provisioner
1) Raspberries Pies version 4 workers

#### Configure hypervisor network
In order to ensure flawless communication between RPi4 - host- vm, it is required to first setup a bridge 
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

#### Create virtual machine
Ensure virtual machine is connected to the previously created bridge and it does not block traffic for http, https, dhcp, bootpc, tftp, nfs, mountd, rpc-bind.\
On centos 7:  
```bash
firewall-cmd --permanent --add-service nfs3
firewall-cmd --permanent --add-service mountd
firewall-cmd --permanent --add-service rpc-bind
firewall-cmd --permanent --add-service tftp
firewall-cmd --permanent --add-service dhcp
firewall-cmd --permanent --add-service bootpc
firewall-cmd --permanent --add-service http
firewall-cmd --permanent --add-service https
```
#### Prepare raspberries pies
Take them out of the box.

## Installation and configuration of the provisioner and RPi4
### Install tinkerbell
Connect to the virtual machine and follow steps from https://tinkerbell.org/setup/prep_provisioner/ .
At the end of installation, envrc file should be created, note its location.

### Setup nfs and tftp
Unfortunately the tinkerbell native method for provisioning os image won't work out of the box with the
raspberries pies (version4), because they don't support fully yet the ipxe (https://github.com/pftf/RPi4 is missing firmware for the lan port). 
So it is required to setup workaround for booting them and invoke tinkerbell workflow. The workaround consist of configuring them to
boot using netboot and load their root filesystem from nfs server. Once loaded, the system will invoke the process responsible 
for the workflow execution - workflow-helper. 

Plan of execution:
1. RPi boots and gets IP from boots
1. RPi downloads firmware from tftp
1. RPi mounts read-only nfs with
docker and tinkerbell tooling (workflow-helper) preinstalled
1. workflow-helper executes workflow in docker according
to instructions from tink (workflow template)
and communicates with hegel to gather necessary info

Schema:

![Alt text](img/tinkerbell-rpi-workaround.png "workaround plan")

#### Configure nfs
First step to enable netboot is to configure nfs server:
1) Source `envrc` created during tinkerbell installation
1) Ensure `unzip kpartx nfs-kernel-server nfs-utils xinetd tftp-server` are installed
1) Create nfs mount point:
     ```bash
    mkdir -p /nfs/os
    ```
1) Download and unzip latest version of raspbian os, rename it for simplicity
    ```bash
    wget https://downloads.raspberrypi.org/raspbian_lite_latest
    unzip raspbian_latest && mv *-raspbian-buster-lite.img raspbian-buster-lite.img
    ```
1) Mount image partitions as loop devices
    ```bash
    kpartx -a -v raspbian-buster-lite.img
    mkdir p1 p2
    mount /dev/mapper/loop0p2 p2/ && mount /dev/mapper/loop0p1 p1/
    ```
1) Copy content of the image to nfs mount point
    ```bash
    cp -rf p2/* /nfs/os
    cp -rf p1/* /nfs/os/boot
    umount p2 p1
    ```
 1) Download upstream firmware and replace the old one
     ```bash
    rm /nfs/os/boot/start4.elf && rm /nfs/os/boot/fixup4.dat
    wget https://github.com/Hexxeh/rpi-firmware/raw/master/start4.elf && wget https://github.com/Hexxeh/rpi-firmware/raw/master/fixup4.dat
    mv start4.elf fixup4.elf /nfs/os/boot/
    ```
 1) Populate `provisioner/nfs/boot/cmdline.txt` with appropriate data and replace `cmdline.txt`  from `/nfs/os/boot` with it.
    ```bash
     cat provisioner/nfs/boot/cmdline.txt | envsubst > /nfs/os/boot/cmdline.txt
     ``` 
 1) Copy files from `provisioner/nfs/{bin,etc,lib/systemd/system}`to corresponding locations:
    ```bash
    cp -f provisioner/nfs/bin/* /nfs/os/bin/
    cp -f provisioner/nfs/etc/* /nfs/os/etc/
    cp -f provisioner/nfs/lib/systemd/system/* /nfs/os/lib/systemd/system
    ```  
 1) Enable ssh at the boot time: `touch /nfs/os/boot/ssh`  
 1) Export os directory
    ```bash
    echo '/nfs/os *(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports
    ```
#### Configure tftp
The next step is to configure tftp server:
1) Source `envrc` created during tinkerbell installation
1) Relax SELinux policy for tftp service
    ```bash
    setsebool -P tftp_home_dir 1
    ```
1) Create directory to serve from:
    ```bash
    mkdir /tftp
    ```    
1) Modify tftp server configuration to bind to the specific interface and set directory. Unfortunately the 
tinkerbell builtin tftp service is unable to handle files requested by RPi4, so in order to work around this, 
we need to setup another tftp server next to boots. We must ensure that it does not listen on the same ip address,
because it won't even start in that case, so in the configuration we should explicitly bind it to the 2nd ip address of 
the interface used by tinkerbell. Tinkerbell during its setup adds another ip which is used by nginx service, we will reuse
it for tftp server as well.\
Modify `/etc/xinetd.d/tftp`:
    ```bash
   cat << EOF | envsubst > /etc/xinetd.d/tftp
    service tftp
    {
            socket_type             = dgram
            protocol                = udp
            wait                    = yes
            user                    = root
            server                  = /usr/sbin/in.tftpd
            bind                    = ${TINKERBELL_NGINX_IP}
            server_args             = -v -v -s /tftp
            disable                 = no
            per_source              = 11
            cps                     = 100 2
            flags                   = IPv4
    }
   EOF
    ```
 
#### Enable both services
Execute: 
```bash
systemctl enable xinetd rpc-bind nfs-server
systemct restart xinetd rpc-bind nfs-server
```  
   
### Raspberry Pi

Next step, before we start nfs and tftp services is to actually configure raspberries pies to boot fron the
network. 
1) Install raspbian os on sd card and plug it into your raspberry pi. 
1) Once booted, connect to it as root and go to `/lib/firmware/raspberrypi/bootloader/stable/`
1) Create boot configuration file, remember to replace `TFTP_IP` with correct ip address (`${TINKERBELL_NGINX_IP}`) created in the previous step:
    ```bash
    cat <<EOF > bootconf.cfg
    [all]
    BOOT_UART=0
    WAKE_ON_GPIO=1
    POWER_OFF_ON_HALT=0
    DHCP_TIMEOUT=45000
    DHCP_REQ_TIMEOUT=4000
    TFTP_FILE_TIMEOUT=30000
    TFTP_IP=${TINKERBELL_NGINX_IP}
    TFTP_PREFIX=0
    BOOT_ORDER=0x21
    SD_BOOT_MAX_RETRIES=3
    NET_BOOT_MAX_RETRIES=5
    [none]
    FREEZE_VERSION=0
    EOF
    ```
1) Create new boot image using the most recent boot image available in the stable directory:
    ```bash
    rpi-eeprom-config --out netboot-pieeprom.bin --config bootconf.cfg pieeprom-2020-04-16.bin
    ```
    **Note:** adjust pieeprom date accordingly to the content of the beta directory
1) Flash eeprom with the new boot image:
    ```bash
    rpi-eeprom-update -d -f netboot-pieeprom.bin
    ```
1) Take note of the RPi4 serial number (especially the last 8 characters) and mac address, it will be used in the next steps: 
    ```bash
    serial=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2) && mac=$(ip link show dev eth0 | grep ether | awk '{print $2}'); 
    printf "serial: %s\nmac: %s\n" ${serial: -8} ${mac}
    ```
1) Repeat above steps for all your RPies.
1) In one of the raspberries pies, connect it to the internet and do the following:
    1) Mount the earlier created nfs directory
        ```bash
        mount -t nfs ${TINKERBELL_HOST_IP}:/nfs/os /mnt
        ```
    1) Chroot into it and mount all partitions:
        ```bash
        cd /mnt && chroot `pwd` /bin/bash && mount -a
        ```
    1) Download and install docker, jq, wget, curl 
        ```bash
        apt-get update && apt-get install -y curl wget jq && curl -sSL https://get.docker.com | sh
        ```
     1) Enable required services and disable unneeded one:
        ```bash
        systemctl enable docker workflow-helper sshd wpa_supplicant 
        systemctl disable bluetooth       
        ```
     1) Exit `chroot` and `umount /mnt`
     1) Optionally configure wifi:
        ```bash
        cp /etc/wpa_supplicant/wpa_supplicant.conf /mnt/etc/wpa_supplicant/wpa_supplicant.conf
        ```  
      
1) If you plan on using the same sd card during workflow execution, ensure to destroy partition table:
    ```bash
    dd if=/dev/zero of=/dev/mmcblk0 bs=1M count=1
    ```
   It is required to do this, because otherwise raspberry pi will boot from sd card first and not from network.
   If not eject sd card and inject empty one.
1) Turn off RPi4.

### Final step
1) In the tftp directory, create directories with RPi serial numbers:
    ```bash
    mkdir -p /tftp/<RPi serial number>
    ```
1) Mount-bind the required boot files to created directories:
    ```bash
    cd /tftp/; for i in `ls`; do mount -o bind /nfs/os/boot /tftp/$i; done ;cd -
    ```
   **Note:** If you want to persist mounts across reboots, update /etc/fstab: 
   ```bash
    echo "/nfs/os/boot /tftp/<rpi serial number> none defaults,bind 0 0" >> /etc/fstab
    ```
 
 ## Configure workflows
 Workflow is a set of task which are executed in order and are used to configure the bare metal machine. 
 Each of the task is executed in th separate docker container. All task are supervised by a tink-worker, which
 gathers logs, communicates with external services and handles errors.
 ### Prepare workflow
 Since workflows are executed in-memory on raspberry pi, it is required ensure tink-worker support that architecture, at the time 
 of writing it was not available, but we prepared one for you, you can pull it from here:
 ```bash
docker pull ottovsky/tink-worker:armv7
```
Once pulled, tag it with your ${TINKERBELL_HOST_IP} registry and push it:
````bash
docker tag ottovsky/tink-worker:armv7 ${TINKERBELL_HOST_IP}/tink-worker:armv7
docker push ${TINKERBELL_HOST_IP}/tink-worker:armv7
````

Next follow instructions from workflow directory.

### Create workflow
1) Source `envrc`
1) Register raspberries pies hardware in tinkerbell
    ```bash
    export hw=$(cat templates/hw.json | envsubst UUID="$(uuidgen)" IP="<desired ip>" MASK="255.255.255.0" MAC="<mac of RPi>" HOSTNAME="hostname")
    docker exec -ti deploy_tink-cli_1 tink hardware push "$hw"
    ```
   Example output after all RPi were registered:
   ````bash
    docker exec -ti deploy_tink-cli_1 tink hardware all
    {"id": "5156f2b7-b0bc-403d-a3f7-5a2db8a40918", "arch": "aarch64", "hostname": "master-1", "allow_pxe": true, "ip_addresses": [{"address": "192.168.2.35", "netmask": "255.255.255.0", "address
    _family": 4}], "network_ports": [{"data": {"mac": "dc:a6:32:7a:28:91"}, "name": "eth0", "type": "data"}], "allow_workflow": true}
    {"id": "e247beba-0a29-4f76-91f5-c74e89b8b74d", "arch": "aarch64", "hostname": "worker-1", "allow_pxe": true, "ip_addresses": [{"address": "192.168.2.36", "netmask": "255.255.255.0", "address
    _family": 4}], "network_ports": [{"data": {"mac": "dc:a6:32:7a:2a:65"}, "name": "eth0", "type": "data"}], "allow_workflow": true}
    {"id": "9f26de7a-3149-4833-a453-8a73e95a1d53", "arch": "aarch64", "hostname": "worker-2", "allow_pxe": true, "ip_addresses": [{"address": "192.168.2.37", "netmask": "255.255.255.0", "address
    _family": 4}], "network_ports": [{"data": {"mac": "dc:a6:32:7a:29:e1"}, "name": "eth0", "type": "data"}], "allow_workflow": true}
   ````
1) Create targets: \
For each of RPi run, replace desired ip with previously defined ip:
    ```bash
    docker exec -ti deploy_tink-cli_1 tink target create '{"targets": {"machine1": {"ipv4_addr": "<desired ip>"}}}' 
    ```
    Note down ids of the created targets. \
    Example output of all created targets:
    ```bash
    docker exec -ti deploy_tink-cli_1 tink target list
    +--------------------------------------+----------------------------------------------------------+
    | TARGET ID                            | TARGET DATA                                              |
    +--------------------------------------+----------------------------------------------------------+
    | 551ff1ae-1a98-4f81-8a5d-60d0b7d23238 | {"targets": {"machine1": {"ipv4_addr": "192.168.2.37"}}} |
    | 0f14482c-bec8-4b43-9eb1-d31311b46d1f | {"targets": {"machine1": {"ipv4_addr": "192.168.2.35"}}} |
    | 83ba628d-62a2-479e-b7af-9606b73d12a8 | {"targets": {"machine1": {"ipv4_addr": "192.168.2.36"}}} |
    +--------------------------------------+----------------------------------------------------------+
    ```
1) Create templates
    ```bash
    export SSID=<wifi ssid>
    export PSK=<wifi psk>
    export COUNTRY=<wifi country>
    export SECRET=<k8s secret>
    export K3S="https://<master ip>:6443 
    cat templates/workflow-master.tmpl | envsubst > k8s-master.tmpl
    cat templates/workflow-worker.tmpl | envsubst > k8s-worker.tmpl
    docker cp k8s-master.tmpl deploy_tink-cli_1:/root
    docker cp k8s-worker.tmpl deploy_tink-cli_1:/root
    docker exec -ti deploy_tink-cli_1 tink template create -n k8s-master -p /root/k8s-master.tmpl
    docker exec -ti deploy_tink-cli_1 tink template create -n k8s-worker -p /root/k8s-worker.tmpl
    ```
    Note down the returned ids of the templates. \
    Example output of created templates:
    ```bash
    docker exec -ti deploy_tink-cli_1 tink template list
    +--------------------------------------+---------------+-------------------------------+-------------------------------+
    | TEMPLATE ID                          | TEMPLATE NAME | CREATED AT                    | UPDATED AT                    |
    +--------------------------------------+---------------+-------------------------------+-------------------------------+
    | 4c4deca8-7e80-4518-9729-4874a166a729 | k8s-master    | 2020-05-07 08:07:31 +0000 UTC | 2020-05-07 08:07:31 +0000 UTC |
    | b6fa353b-d20e-434d-9652-4ebe5231257b | k8s-worker    | 2020-05-07 08:05:57 +0000 UTC | 2020-05-07 08:05:57 +0000 UTC |
    +--------------------------------------+---------------+-------------------------------+-------------------------------+
    ```

1) Create workflows, in orderd to this, it is required to assign template id with target id.
    ```bash
    docker exec -ti deploy_tink-cli_1 tink workflow create -t <template id> -r <target id>
    ```
    In this step, you decide what role should be assigned to RPi. for example if you would like one RPi to be k8s master, 
    you have to assign target with its IP to the k8s-master template.
    Note down the workflow ids.

 ## Execute workflow
 
 Insert empty sd card to the raspberry pi and power it up. Wait till the workflow is executed:
 ```bash
docker exec -ti deploy_tink-cli_1 tink workflow events <workflow id> 
+--------------------------------------+------------------+--------------+----------------+---------------------------------+--------------------+
| WORKER ID                            | TASK NAME        | ACTION NAME  | EXECUTION TIME | MESSAGE                         |      ACTION STATUS |
+--------------------------------------+------------------+--------------+----------------+---------------------------------+--------------------+
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | disk-wipe    |              0 | Started execution               | ACTION_IN_PROGRESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | disk-wipe    |             11 | Finished Execution Successfully |     ACTION_SUCCESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | os-install   |              0 | Started execution               | ACTION_IN_PROGRESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | os-install   |            501 | Finished Execution Successfully |     ACTION_SUCCESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | os-configure |              0 | Started execution               | ACTION_IN_PROGRESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | os-configure |              3 | Finished Execution Successfully |     ACTION_SUCCESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | install-k8s  |              0 | Started execution               | ACTION_IN_PROGRESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | install-k8s  |             19 | Finished Execution Successfully |     ACTION_SUCCESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | reboot       |              0 | Started execution               | ACTION_IN_PROGRESS |
| 5156f2b7-b0bc-403d-a3f7-5a2db8a40918 | k8s-installation | reboot       |             14 | Finished Execution Successfully |     ACTION_SUCCESS |
+--------------------------------------+------------------+--------------+----------------+---------------------------------+--------------------+

```

Once the workflow finished, the RPi should be an operational k8s master/worker node.