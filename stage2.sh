#!/bin/bash

set -x

NODE=$1
OCP_VERSION=latest-4.7

scp net-baremetal.xml net-provisioning.xml net-cnv.xml root@${NODE}:/tmp/
ssh root@${NODE} 'virsh net-define /tmp/net-baremetal.xml && virsh net-autostart baremetal && virsh net-start baremetal'
ssh root@${NODE} 'virsh net-define /tmp/net-provisioning.xml && virsh net-autostart provisioning && virsh net-start provisioning'

ssh root@${NODE} 'for VM in ocp{0..2} ; do qemu-img create -f qcow2 /var/lib/libvirt/images/${VM}.qcow2 200G ; done'
ssh root@${NODE} wget -P /var/lib/libvirt/images http://10.11.173.1/pub/CNV-2.5-hackfest/provisioner.qcow2

ssh root@${NODE} virt-install -n provisioner --memory 16384 --vcpus 4 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/provisioner.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:05:00,target=provif \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:00:00 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virsh start provisioner

ssh root@${NODE} virt-install -n ocp0 --memory 32768 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/ocp0.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:00 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:00 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n ocp1 --memory 32768 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/ocp1.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:01 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:01 \
	--controller scsi,model=virtio-scsi --import --noreboot

ssh root@${NODE} virt-install -n ocp2 --memory 32768 --vcpus 6 --cpu host --os-variant rhel8.2 \
	--disk path=/var/lib/libvirt/images/ocp2.qcow2,bus=scsi,discard=unmap \
	-w network=provisioning,model=virtio,mac=de:ad:be:ef:03:02 \
	-w network=baremetal,model=virtio,mac=de:ad:be:ef:01:02 \
	--controller scsi,model=virtio-scsi --import --noreboot

scp python2-pyghmi-1.0.44-1.1.el7.noarch.rpm python2-virtualbmc-1.2.0-1.1.el7.noarch.rpm root@${NODE}:/tmp/
ssh root@${NODE} yum -y install /tmp/python2-pyghmi-1.0.44-1.1.el7.noarch.rpm /tmp/python2-virtualbmc-1.2.0-1.1.el7.noarch.rpm

ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.248 ocp0
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.249 ocp1
ssh root@${NODE} vbmc add --username admin --password CNV25h@ck --address 192.168.123.250 ocp2

scp vbmc@.service root@${NODE}:/etc/systemd/system/
ssh root@${NODE} systemctl daemon-reload
ssh root@${NODE} systemctl enable --now vbmc@ocp{0..2}

ssh root@${NODE} yum -y install squid
ssh root@${NODE} systemctl enable squid --now

# Host seems to have problems resolving prov on the first few tries; weird
while ! ssh root@${NODE} ping -c1 prov ; do
	sleep 1
done

ssh root@${NODE} yum -y install sshpass
ssh root@${NODE} 'ssh-keygen -t rsa -q -f ~/.ssh/id_rsa -N ""'
ssh root@${NODE} 'echo CNV25h@ck | sshpass ssh-copy-id -oStrictHostKeyChecking=no kni@prov'
ssh root@${NODE} 'cat .ssh/authorized_keys | ssh kni@prov "cat - >> .ssh/authorized_keys"'

ssh -J root@${NODE} kni@prov 'rm -rf *'
scp -J root@${NODE} ocp{0..2}-install-config.yaml pull-secret.txt ocp-deploy.sh ocp-api-inject.sh kni@prov:
ssh -J root@${NODE} kni@prov 'jq -c . pull-secret.txt > pull-secret.json'

for YAML in ocp{0..2}-install-config.yaml ; do
	ssh -J root@${NODE} kni@prov "echo -n \"pullSecret: '\" >> $YAML"
	ssh -J root@${NODE} kni@prov "cat pull-secret.json | tr -d \\\\n >> $YAML"
	ssh -J root@${NODE} kni@prov "echo \"'\" >> $YAML"
	ssh -J root@${NODE} kni@prov "echo -n \"sshKey: '\" >> $YAML"
	ssh -J root@${NODE} kni@prov "cat .ssh/id_rsa.pub | tr -d \\\\n >> $YAML"
	ssh -J root@${NODE} kni@prov "echo \"'\" >> $YAML"
done

OCP_RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
OCP_CLIENT_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz

ssh -J root@${NODE} kni@prov "curl -s $OCP_CLIENT_URL | tar xz oc"
ssh -J root@${NODE} kni@prov "./oc adm release extract --registry-config pull-secret.txt --command openshift-baremetal-install $OCP_RELEASE_IMAGE"
ssh -J root@${NODE} kni@prov 'sudo cp oc openshift-baremetal-install /usr/local/bin/ && rm oc openshift-baremetal-install'

