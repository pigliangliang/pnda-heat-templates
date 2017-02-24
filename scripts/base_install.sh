#!/bin/bash -v

# This script runs on all instances except the saltmaster
# It installs a salt minion and mounts the disks

set -ex
DISTRO=$(cat /etc/*-release|grep ^ID\=|awk -F\= {'print $2'}|sed s/\"//g)

if [ "x$DISTRO" == "xubuntu" ]; then
rm -rf /etc/apt/sources.list.d/*
rm -rf /etc/apt/sources.list
touch /etc/apt/sources.list
cat > /etc/apt/sources.list.d/local.list <<EOF
  deb $pnda_mirror$/debs/ ./
EOF
wget -O - $pnda_mirror$/debs/pnda.gpg.key | apt-key add -
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install xfsprogs salt-minion
elif [ "x$DISTRO" == "xrhel" ]; then
rm -rf /etc/yum.repos.d/*
yum-config-manager --add-repo $pnda_mirror$/rpms
rpm --import $pnda_mirror$/rpms/RPM-GPG-KEY-redhat-release
rpm --import $pnda_mirror$/rpms/RPM-GPG-KEY-mysql
rpm --import $pnda_mirror$/rpms/RPM-GPG-KEY-cloudera
rpm --import $pnda_mirror$/rpms/RPM-GPG-KEY-EPEL-7
rpm --import $pnda_mirror$/rpms/SALTSTACK-GPG-KEY.pub
rpm --import $pnda_mirror$/rpms/RPM-GPG-KEY-CentOS-7
yum -y install xfsprogs wget salt-minion
fi

ROLES=$roles$

cat >> /etc/hosts <<EOF
$master_ip$ saltmaster salt
EOF

if [ "x$DISTRO" == "xubuntu" ]; then
export DEBIAN_FRONTEND=noninteractive
fi

hostname=`hostname` && echo "id: $hostname" > /etc/salt/minion && unset hostname
echo "log_level: debug" >> /etc/salt/minion
echo "log_level_logfile: debug" >> /etc/salt/minion

# Set up the grains
cat > /etc/salt/grains <<EOF
pnda:
  flavor: $flavor$
pnda_cluster: $pnda_cluster$
EOF

# The cloudera:role grain is used by the cm_setup.py (in platform-salt) script to
# place specific cloudera roles on this instance.
# The mapping of cloudera roles to cloudera:role grains is
# defined in the cfg_<flavor>.py.tpl files (in platform-salt)
if [ "$cloudera_role$" != "$" ]; then
  cat >> /etc/salt/grains <<EOF
cloudera:
  role: $cloudera_role$
EOF
fi

if [ "$brokerid$" != "$" ]; then
  cat >> /etc/salt/grains <<EOF
broker_id: $brokerid$
EOF
fi

# The roles grains determine what software is installed
# on this instance by platform-salt scripts
if [ "x${ROLES}" != "x" ]; then
cat >> /etc/salt/grains <<EOF
roles: [${ROLES}]
EOF
fi

if [ "$pip_index_url$" != "$" ] ; then
TRUSTED_HOST=$(echo '$pip_index_url$' | awk -F'[/:]' '/http:\/\//{print $4}')
cat << EOF >> /etc/pip.conf
[global]
index-url=$pip_index_url$
trusted-host=$TRUSTED_HOST
EOF
cat << EOF >> /root/.pydistutils.cfg
[easy_install]
index_url=$pip_index_url$
EOF
fi

if [ "x$DISTRO" == "xubuntu" ]; then
service salt-minion restart

# Mount the disks
LOG_VOLUME_ID="$log_volume_id$"
LOG_VOLUME_DEVICE="/dev/disk/by-id/virtio-$(echo ${LOG_VOLUME_ID} | cut -c -20)"
echo LOG_VOLUME_DEVICE is $LOG_VOLUME_DEVICE
if [ -b $LOG_VOLUME_DEVICE ]; then
  echo LOG_VOLUME_DEVICE exists
  umount $LOG_VOLUME_DEVICE || echo 'not mounted'
  mkfs.xfs $LOG_VOLUME_DEVICE
  mkdir -p /var/log/pnda
  cat >> /etc/fstab <<EOF
  $LOG_VOLUME_DEVICE  /var/log/pnda xfs defaults  0 0
EOF
fi

HDFS_VOLUME_ID="$hdfs_volume_id$"
HDFS_VOLUME_DEVICE="/dev/disk/by-id/virtio-$(echo ${HDFS_VOLUME_ID} | cut -c -20)"
echo HDFS_VOLUME_DEVICE is $HDFS_VOLUME_DEVICE
if [ -b $HDFS_VOLUME_DEVICE ]; then
  echo HDFS_VOLUME_DEVICE exists
  umount $HDFS_VOLUME_DEVICE || echo 'not mounted'
  mkfs.xfs $HDFS_VOLUME_DEVICE
  mkdir -p /data0
  cat >> /etc/fstab <<EOF
  $HDFS_VOLUME_DEVICE  /data0 xfs defaults  0 0
EOF
fi

if [[ "$package_repository_fs_type$" == "local" ]]; then
  PR_VOLUME_ID="$pr_volume_id$"
  PR_VOLUME_DEVICE="/dev/disk/by-id/virtio-$(echo ${PR_VOLUME_ID} | cut -c -20)"
  echo PR_VOLUME_DEVICE is $PR_VOLUME_DEVICE
  if [ -b $PR_VOLUME_DEVICE ]; then
    echo PR_VOLUME_DEVICE exists
    umount $PR_VOLUME_DEVICE || echo 'not mounted'
    mkfs.xfs $PR_VOLUME_DEVICE
    mkdir -p $package_repository_fs_location_path$
    cat >> /etc/fstab <<EOF
    $HDFS_VOLUME_DEVICE  $package_repository_fs_location_path$ xfs defaults  0 0
EOF
  fi
fi

cat /etc/fstab
mount -a
