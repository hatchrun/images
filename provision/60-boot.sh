#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Gamunu Balagalla <gamunu.balagalla@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# A runner instance lives for one job, so every second of boot is spent
# per job. Ubuntu orders cloud-init before every regular service and it
# took about 20 of the 37 seconds before hatchrun-agent started, mostly
# probing datasources and generating keys a runner never uses. The image
# boots without it. The network, the launch key pair and growing the
# root file system are done by the small units below, and only the
# network is on the agent's path. sshd-keygen.service makes the host
# keys.
#
# User data is read by hatchrun-agent alone. Scripts in user data do not
# run on this image.

touch /etc/cloud/cloud-init.disabled

# DHCP on the primary interface. The file cloud-init wrote for the
# builder matches the builder's MAC address and would leave a runner
# without a network.
rm -f /etc/netplan/50-cloud-init.yaml
install -m 0600 /dev/stdin /etc/netplan/50-hatchrun.yaml <<'NETPLAN'
network:
  version: 2
  ethernets:
    primary:
      match:
        name: "en*"
      dhcp4: true
      dhcp6: false
NETPLAN

# The hostname comes from DHCP, so each runner has its own.
rm -f /etc/hostname

install -d -m 0755 /usr/local/libexec
install -m 0755 /dev/stdin /usr/local/libexec/hatchrun-ssh-key <<'SCRIPT'
#!/bin/sh
# Installs the launch key pair's public key for the ubuntu user, so an
# operator, and the AWS Marketplace scan, can log in. An instance
# launched without a key pair gets no key.
set -eu
imds=http://169.254.169.254
token=$(curl -sf -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' "${imds}/latest/api/token")
key=$(curl -sf -H "X-aws-ec2-metadata-token: ${token}" "${imds}/latest/meta-data/public-keys/0/openssh-key") || exit 0
install -d -m 0700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
printf '%s\n' "${key}" > /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys
chmod 0600 /home/ubuntu/.ssh/authorized_keys
SCRIPT

install -m 0755 /dev/stdin /usr/local/libexec/hatchrun-growroot <<'SCRIPT'
#!/bin/sh
# Grows the root partition and file system to the volume the launch
# template asked for. growpart exits 1 when there is nothing to grow.
set -eu
part=$(findmnt -no SOURCE /)
disk=/dev/$(lsblk -no PKNAME "${part}")
number=$(cat "/sys/class/block/$(basename "${part}")/partition")
growpart "${disk}" "${number}" || [ $? -eq 1 ]
resize2fs "${part}"
SCRIPT

install -m 0644 /dev/stdin /etc/systemd/system/hatchrun-ssh-key.service <<'UNIT'
[Unit]
Description=Install the launch key pair for the ubuntu user
Wants=network-online.target
After=network-online.target
Before=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/hatchrun-ssh-key

[Install]
WantedBy=multi-user.target
UNIT

install -m 0755 /dev/stdin /usr/local/libexec/hatchrun-prefetch <<'SCRIPT'
#!/bin/sh
# A volume made from a snapshot fetches each block from S3 the first
# time it is read. The runner and Docker read their files one by one at
# start and took 15 and 20 seconds doing it. Reading the same files many
# at a time fetches them far faster, in the order they are needed.
prefetch() {
  find "$@" -type f -print0 2> /dev/null | xargs -0 -r -P 64 -n 16 cat > /dev/null 2>&1
}
prefetch /home/runner/bin
prefetch /usr/bin/dockerd /usr/bin/containerd /usr/bin/containerd-shim-runc-v2 \
  /usr/bin/runc /usr/bin/docker /usr/libexec/docker
prefetch /home/runner/externals
exit 0
SCRIPT

install -m 0644 /dev/stdin /etc/systemd/system/hatchrun-prefetch.service <<'UNIT'
[Unit]
Description=Read the runner and Docker files ahead of their start
DefaultDependencies=no
After=local-fs.target

[Service]
Type=exec
ExecStart=/usr/local/libexec/hatchrun-prefetch

[Install]
WantedBy=sysinit.target
UNIT

install -m 0644 /dev/stdin /etc/systemd/system/hatchrun-growroot.service <<'UNIT'
[Unit]
Description=Grow the root file system to the volume size

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/hatchrun-growroot

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable hatchrun-prefetch.service hatchrun-ssh-key.service hatchrun-growroot.service

# Services a single-job machine has no use for.
for unit in apport.service udisks2.service lvm2-monitor.service multipathd.service \
  multipathd.socket networkd-dispatcher.service dpkg-db-backup.timer motd-news.timer \
  man-db.timer e2scrub_all.timer ec2-instance-connect-harvest-hostkeys.service; do
  if systemctl cat "${unit}" > /dev/null 2>&1; then
    systemctl disable "${unit}"
  fi
done
