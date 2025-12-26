#!/usr/bin/env bash
#
# ==============================================================================
#  openSUSE MicroOS Bootstrap Script
# ==============================================================================
#
#  This script prepares a hardened openSUSE MicroOS host by:
#
#   • Installing and enabling Tailscale
#   • Installing and enabling fail2ban
#   • Installing and configuring syslog-ng to forward ALL logs to a
#     central syslog server called "syslog" over TCP/514
#     - with DISK BUFFERING so logs queue locally if syslog is down
#   • Locking down SSH to key-based auth only (no passwords)
#   • Restricting SSH access to group "ssh-users" with only user "darren"
#   • Pulling SSH keys from https://github.com/soothill.keys
#
#  Uses transactional-update (atomic snapshot changes). Reboot required.
#
# ------------------------------------------------------------------------------
#  Copyright (c) 2025 Darren Soothill
#  All rights reserved.
#
#  Contact (obfuscated): darren [at] soothill [dot] com
# ------------------------------------------------------------------------------
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
USER_NAME="darren"
SSH_GROUP="ssh-users"
GITHUB_USER="soothill"

SYSLOG_HOST="syslog"
SYSLOG_PORT="514"

# Syslog-ng disk buffering
# Where to spool logs if the remote syslog target is unavailable.
# Note: on MicroOS this persists (writable /var).
SYSLOG_BUFFER_DIR="/var/lib/syslog-ng"
SYSLOG_BUFFER_FILE="${SYSLOG_BUFFER_DIR}/syslog-buffer.qf"

# Max size of disk-buffer (tune to taste)
SYSLOG_DISKBUF_SIZE="512M"

# How long to keep messages in buffer if remote stays unavailable (optional)
# 0 means keep until delivered (subject to diskbuf size)
SYSLOG_DISKBUF_RELIABLE="yes"

AUTO_REBOOT="${AUTO_REBOOT:-1}"
TS_AUTHKEY="${TS_AUTHKEY:-}"  # optional

log() { echo "==> $*"; }

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Run as root (or sudo)."
  exit 1
fi

log "Staging configuration into a new MicroOS snapshot..."

transactional-update -n shell <<'EOF'
set -euo pipefail

USER_NAME="darren"
SSH_GROUP="ssh-users"
GITHUB_USER="soothill"

SYSLOG_HOST="syslog"
SYSLOG_PORT="514"

SYSLOG_BUFFER_DIR="/var/lib/syslog-ng"
SYSLOG_BUFFER_FILE="${SYSLOG_BUFFER_DIR}/syslog-buffer.qf"
SYSLOG_DISKBUF_SIZE="512M"
SYSLOG_DISKBUF_RELIABLE="yes"

TS_AUTHKEY="${TS_AUTHKEY:-}"

echo "==> Adding Tailscale repository..."
zypper -n ar -f https://pkgs.tailscale.com/stable/opensuse/tumbleweed tailscale || true
zypper -n --gpg-auto-import-keys refresh

echo "==> Installing packages..."
zypper -n install tailscale syslog-ng fail2ban openssh curl ca-certificates

echo "==> Ensure user + SSH group exist..."
getent group "${SSH_GROUP}" >/dev/null 2>&1 || groupadd "${SSH_GROUP}"

if ! id -u "${USER_NAME}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${USER_NAME}"
fi

# Ensure only USER_NAME is in SSH_GROUP
usermod -aG "${SSH_GROUP}" "${USER_NAME}"
gpasswd -M "${USER_NAME}" "${SSH_GROUP}"

echo "==> Pulling GitHub public keys into authorized_keys..."
home_dir="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
install -d -m 0700 -o "${USER_NAME}" -g "${USER_NAME}" "${home_dir}/.ssh"
curl -fsSL "https://github.com/${GITHUB_USER}.keys" -o "${home_dir}/.ssh/authorized_keys"
chown "${USER_NAME}:${USER_NAME}" "${home_dir}/.ssh/authorized_keys"
chmod 0600 "${home_dir}/.ssh/authorized_keys"

echo "==> Locking down SSH (keys only, group restriction)..."
sshd_cfg="/etc/ssh/sshd_config"
cp "${sshd_cfg}" "${sshd_cfg}.bak.$(date +%Y%m%d%H%M%S)"

set_sshd() {
  local key="$1" val="$2"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]+" "${sshd_cfg}"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${val}|g" "${sshd_cfg}"
  else
    echo "${key} ${val}" >> "${sshd_cfg}"
  fi
}

set_sshd "PasswordAuthentication" "no"
set_sshd "KbdInteractiveAuthentication" "no"
set_sshd "ChallengeResponseAuthentication" "no"
set_sshd "PubkeyAuthentication" "yes"
set_sshd "PermitRootLogin" "no"
set_sshd "UsePAM" "yes"
set_sshd "AllowGroups" "${SSH_GROUP}"
set_sshd "AuthorizedKeysFile" ".ssh/authorized_keys"
set_sshd "MaxAuthTries" "3"
set_sshd "LoginGraceTime" "20"

echo "==> Configuring fail2ban (enable sshd jail)..."
install -d /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled  = true
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5
JAIL

echo "==> Configuring syslog-ng to forward everything to '${SYSLOG_HOST}' with disk buffering..."
install -d /etc/syslog-ng/conf.d
install -d -m 0755 "${SYSLOG_BUFFER_DIR}"

cat >/etc/syslog-ng/conf.d/99-forward-all.conf <<CONF
# -----------------------------------------------------------------------------
# Forward ALL logs to central syslog host over TCP/${SYSLOG_PORT}
# with local disk buffering to survive outages.
#
# Disk buffer notes:
#  - reliable(${SYSLOG_DISKBUF_RELIABLE}) keeps messages on disk until delivered
#  - disk-buf-size(${SYSLOG_DISKBUF_SIZE}) caps spool usage
#  - qfile() path persists in /var (writable on MicroOS)
# -----------------------------------------------------------------------------

destination d_remote_tcp {
  syslog("${SYSLOG_HOST}"
    transport("tcp")
    port(${SYSLOG_PORT})
    flags(syslog-protocol)
    time-reopen(10)

    # Disk buffering (spool to disk when destination is unavailable)
    disk-buffer(
      reliable(${SYSLOG_DISKBUF_RELIABLE})
      disk-buf-size(${SYSLOG_DISKBUF_SIZE})
      qout-size(1000)
      mem-buf-length(10000)
      qfile("${SYSLOG_BUFFER_FILE}")
    )
  );
};

# On openSUSE the default source is typically "src"
log { source(src); destination(d_remote_tcp); };
CONF

echo "==> Enabling services on boot..."
systemctl enable sshd
systemctl enable tailscaled
systemctl enable syslog-ng
systemctl enable fail2ban

echo "==> Optional: auto-enroll Tailscale if TS_AUTHKEY is provided..."
if [[ -n "${TS_AUTHKEY:-}" ]]; then
  tailscale up --authkey="${TS_AUTHKEY}" --accept-dns=false || true
fi

echo "==> Done staging changes into snapshot."
EOF

if [[ "${AUTO_REBOOT}" == "1" ]]; then
  log "Rebooting to activate the new snapshot..."
  transactional-update reboot
else
  log "Snapshot prepared. Reboot when ready: sudo transactional-update reboot"
fi
