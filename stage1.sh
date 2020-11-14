#!/bin/bash

set -x

NODE=$1

ssh root@${NODE} yum -y install epel-release centos-release-openstack-queens
ssh root@${NODE} yum -y update
ssh root@${NODE} firewall-cmd --new-zone baremetal --permanent
ssh root@${NODE} firewall-cmd --zone baremetal --add-service ssh --add-service dns --add-service dhcp --permanent
ssh root@${NODE} firewall-cmd --zone baremetal --add-port 623/udp --permanent
ssh root@${NODE} firewall-cmd --zone public --add-masquerade --permanent
scp ifcfg-metal ifcfg-prov ifcfg-cnv root@${NODE}:/etc/sysconfig/network-scripts/
ssh root@${NODE} 'echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm.conf'
ssh root@${NODE} 'virsh net-destroy default && virsh net-undefine default'
scp resolv.conf dnsmasq.conf root@${NODE}:/etc/
ssh root@${NODE} systemctl enable dnsmasq
ssh root@${NODE} reboot
