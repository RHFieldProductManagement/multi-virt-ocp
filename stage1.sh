#!/bin/bash

set -x

NODE=$1

ssh root@${NODE} yum -y install epel-release centos-release-openstack-queens
ssh root@${NODE} yum -y update
ssh root@${NODE} firewall-cmd --permanent --new-zone baremetal
ssh root@${NODE} firewall-cmd --permanent --zone baremetal --add-service ssh --add-service dns --add-service dhcp
ssh root@${NODE} firewall-cmd --permanent --zone baremetal --add-port 623/udp
ssh root@${NODE} firewall-cmd --permanent --zone public --add-masquerade
ssh root@${NODE} firewall-cmd --permanent --direct --add-chain eb filter FORWARD_prov
ssh root@${NODE} firewall-cmd --permanent --direct --add-rule eb filter FORWARD_prov 10 -i provif -j ACCEPT
ssh root@${NODE} firewall-cmd --permanent --direct --add-rule eb filter FORWARD_prov 10 -o provif -j ACCEPT
ssh root@${NODE} firewall-cmd --permanent --direct --add-rule eb filter FORWARD_prov 90 -j DROP
ssh root@${NODE} firewall-cmd --permanent --direct --add-rule eb filter FORWARD_direct 10 --logical-in prov -j FORWARD_prov
ssh root@${NODE} firewall-cmd --permanent --direct --add-rule eb filter FORWARD_direct 10 --logical-out prov -j FORWARD_prov
scp ifcfg-metal ifcfg-prov ifcfg-cnv root@${NODE}:/etc/sysconfig/network-scripts/
ssh root@${NODE} 'echo "options kvm_intel nested=1" > /etc/modprobe.d/kvm.conf'
ssh root@${NODE} 'virsh net-destroy default && virsh net-undefine default'
scp resolv.conf dnsmasq.conf root@${NODE}:/etc/
ssh root@${NODE} systemctl enable dnsmasq
ssh root@${NODE} reboot
