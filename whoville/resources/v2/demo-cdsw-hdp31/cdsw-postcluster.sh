#!/usr/bin/env bash

# WARNING: This script is only for RHEL7 on EC2

yum -y install iptables-services nfs-utils libseccomp lvm2 bridge-utils libtool-ltdl ebtables rsync policycoreutils-python ntp bind-utils nmap-ncat openssl e2fsprogs redhat-lsb-core socat selinux-policy-base selinux-policy-targeted 

systemctl enable iptables
systemctl restart iptables
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X
systemctl restart iptables

# set java_home on centos7
export JAVA_HOME=$(readlink -f /usr/bin/javac | sed "s:/bin/javac::") >> /etc/profile

# Fetch public IP
#export PUBLIC_IP=$(curl -s https://ipv4.icanhazip.com)
export MASTER_IP=$(hostname --ip-address)

# unmount  vols - Cloudbreak will always mount presented volumes but this isn't a datanode
if lsblk | grep -q xvd ; then
    umount /dev/xvdb
    umount /dev/xvdc
    export DOCKER_BLOCK=/dev/xvdb
    export APP_BLOCK=/dev/xvdc
    sed -i '/hadoopfs/d' /etc/fstab
fi

if lsblk | grep -q nvme ; then
    umount /dev/nvme1n1
    umount /dev/nvme2n1
    export DOCKER_BLOCK=/dev/nvme1n1
    export APP_BLOCK=/dev/nvme2n1
    sed -i '/hadoopfs/d' /etc/fstab
fi

# Set limits
sed -i "s@# End of file@*                soft    nofile         1048576\n*                hard    nofile         1048576\nroot             soft    nofile         1048576\nroot             hard    nofile         1048576\n# End of file@g" /etc/security/limits.conf

# CDSW will break default Amazon DNS on 127.0.0.1:53, so we use a different IP
sed -i "s@127.0.0.1@169.254.169.253@g" /etc/resolv.conf

# Install CDSW
wget -q --no-check-certificate https://s3.eu-west-2.amazonaws.com/whoville/v2/temp.blob
mv temp.blob cloudera-data-science-workbench-1.5.0.818361-1.el7.centos.x86_64.rpm
yum install -y cloudera-data-science-workbench-1.5.0.818361-1.el7.centos.x86_64.rpm

# Install Anaconda
curl -Ok https://repo.anaconda.com/archive/Anaconda2-5.2.0-Linux-x86_64.sh
chmod +x ./Anaconda2-5.2.0-Linux-x86_64.sh
./Anaconda2-5.2.0-Linux-x86_64.sh -b -p /anaconda

# CDSW Setup
sed -i "s@MASTER_IP=\"\"@MASTER_IP=\"${MASTER_IP}\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@JAVA_HOME=\"/usr/java/default\"@JAVA_HOME=\"$(echo ${JAVA_HOME})\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@DOMAIN=\"cdsw.company.com\"@DOMAIN=\"${PUBLIC_IP}.nip.io\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@DOCKER_BLOCK_DEVICES=\"\"@DOCKER_BLOCK_DEVICES=\"${DOCKER_BLOCK}\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@APPLICATION_BLOCK_DEVICE=\"\"@APPLICATION_BLOCK_DEVICE=\"${APP_BLOCK}\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@DISTRO=\"\"@DISTRO=\"HDP\"@g" /etc/cdsw/config/cdsw.conf
sed -i "s@ANACONDA_DIR=\"\"@ANACONDA_DIR=\"/anaconda/bin\"@g" /etc/cdsw/config/cdsw.conf

cdsw init