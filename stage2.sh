#!/bin/bash

set -x

NODE=$1

scp net-baremetal.xml net-provisioning.xml net-cnv.xml root@${NODE}:/tmp/
ssh root@${NODE} 'virsh net-define /tmp/net-baremetal.xml && virsh net-autostart baremetal && virsh net-start baremetal'
ssh root@${NODE} 'virsh net-define /tmp/net-provisioning.xml && virsh net-autostart provisioning && virsh net-start provisioning'
ssh root@${NODE} 'virsh net-define /tmp/net-cnv.xml && virsh net-autostart cnv && virsh net-start cnv'

ssh root@${NODE} 'for VM in {master,worker}-{0..2} ; do qemu-img create -f qcow2 /var/lib/libvirt/images/${VM}.qcow2 120G ; done'
ssh root@${NODE} wget -P /var/lib/libvirt/images http://10.11.173.1/pub/CNV-2.5-hackfest/provisioner.qcow2

ssh root@${NODE} virt-install -n provisioner --memory 16384 --vcpus 4 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/provisioner.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:05:00 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:00:00 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virsh start provisioner

ssh root@${NODE} virt-install -n master-0 --memory 24576 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/master-0.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:00 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:00 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n master-1 --memory 24576 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/master-1.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:01 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:01 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n master-2 --memory 24576 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/master-2.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:02 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:02 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n worker-0 --memory 16384 --vcpus 4 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/worker-0.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:04:00 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:02:00 \
	-w network=cnv,model=virtio --controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n worker-1 --memory 16384 --vcpus 4 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/worker-1.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:04:01 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:02:01 \
	-w network=cnv,model=virtio --controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n worker-2 --memory 16384 --vcpus 4 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/worker-2.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:04:02 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:02:02 \
	-w network=cnv,model=virtio --controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} yum -y install python2-virtualbmc
ssh root@${NODE} yum -y update http://10.11.173.1/pub/CNV-2.5-hackfest/python2-pyghmi-1.0.22-1.1.el7.noarch.rpm

ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.248 master-0
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.249 master-1
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.250 master-2
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.251 worker-0
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.252 worker-1
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.253 worker-2

scp vbmc@.service root@${NODE}:/etc/systemd/system/
ssh root@${NODE} systemctl daemon-reload
ssh root@${NODE} systemctl enable --now vbmc@{master,worker}-{0..2}

ssh root@${NODE} yum -y install squid
ssh root@${NODE} systemctl enable squid --now
