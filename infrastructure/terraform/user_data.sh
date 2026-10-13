#!/usr/bin/env bash
set -euo pipefail

# 1. Expand root EBS volume if enlarged
growpart /dev/nvme0n1 1 || growpart /dev/xvda 1 || true
resize2fs /dev/nvme0n1p1 || resize2fs /dev/root || resize2fs /dev/xvda1 || true

# 2. Prevent Ubuntu unattended-upgrades from locking apt during Ansible deployment
systemctl stop unattended-upgrades.service apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
systemctl disable unattended-upgrades.service apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
