#!/usr/bin/env bash
#
# ==============================================================================
#  openSUSE MicroOS Bootstrap Script
#  - transactional-update snapshot for packages + /etc config
#  - first-boot oneshot for /home + authorized_keys (runs on LIVE system)
#  - persistent Tailscale ethtool perf tuning (runs on every boot)
# ==============================================================================
#
# Snapshot part (transactional-update):
#  • Add/refresh Tailscale repo (idempotent)
#  • Install: tailscale, fail2ban, syslog-ng, ethtool, openssh, curl
#  • Configure syslog-ng: forward all -> host "syslog" TCP/514 + disk buffering
#  • Harden SSH using drop-in: keys only, no root, AllowGroups=ssh-users
#  • Ensure ssh-users group exists; ensure user darren exists (NO home creation here)
#  • Install systemd oneshots:
#      - microos-firstboot-homekeys.service (runs once after reboot on LIVE FS)
#      - tailscale-ethtool.service (runs every boot, uses /etc/tailscale script)
#
# ------------------------------------------------------------------------------
#  Copyright (c) 2025 Darren Soothill
#  All rights reserved.
#
#  Contact (obfuscated): darren [at] soothill [dot] com
# ------------------------------------------------------------------------------

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
USER_NAME="darren"
SSH_GROUP="ssh-users"
GITHUB_USER="soothill"

SYSLOG_HOST="syslog"
SYSLOG_PORT="514"

SYSLOG_BUFFER_DIR="/var/lib/syslog-ng"
SYSLOG_BUFFER_FILE="${SYSLOG_BUFFER_DIR}/syslog-buffer.qf"
SYSLOG_DISKBUF_SIZE="512M"
SYSLOG_DISKBUF_RELIABLE="yes"

AUTO_REBOOT="${AUTO_REBOOT:-1}"
TS_AUTHKEY="${TS_AUTHKEY:-}"   # optional

log() { echo "==> $*"; }

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Run as root (or via sudo)."
  exit 1
fi

export TS_AUTHKEY

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

# --------------------------------------------------------------------------
# Tailscale repo (idempotent): remove any pkgs.tailscale.com repos, then add
# --------------------------------------------------------------------------
echo "==> Ensuring correct Tailscale repository is configured..."
existing_repo_aliases="$(zypper lr -u | awk '/pkgs\.tailscale\.com/ {print $1}')"
if [[ -n "${existing_repo_aliases}" ]]; then
  echo "==> Removing existing Tailscale repo(s): ${existing_repo_aliases}"
  for repo in ${existing_repo_aliases}; do
    zypper -n rr "${repo}"
  done
fi

echo "==> Adding correct Tailscale repo (.repo file)..."
zypper -n ar -g -r https://pkgs.tailscale.com/stable/opensuse/tumbleweed/tailscale.repo
zypper -n --gpg-auto-import-keys refresh

# --------------------------------------------------------------------------
# Install packages
# --------------------------------------------------------------------------
echo "==> Installing packages..."
zypper -n install \
  tailscale \
  syslog-ng \
  fail2ban \
  openssh \
  curl \
  ca-certificates \
  ethtool

# --------------------------------------------------------------------------
# Ensure SSH access group and user exist (DO NOT create /home in snapshot)
# --------------------------------------------------------------------------
echo "==> Ensuring SSH access group exists..."
getent group "${SSH_GROUP}" >/dev/null 2>&1 || groupadd "${SSH_GROUP}"

echo "==> Ensuring user exists (without creating /home in snapshot)..."
if ! id -u "${USER_NAME}" >/dev/null 2>&1; then
  # Create user entry; home will be created on live FS by oneshot
  useradd -M -s /bin/bash "${USER_NAME}"
fi
usermod -aG "${SSH_GROUP}" "${USER_NAME}" || true

# --------------------------------------------------------------------------
# SSH hardening via drop-in (avoids assuming /etc/ssh/sshd_config exists)
# --------------------------------------------------------------------------
echo "==> Hardening SSH configuration via /etc/ssh/sshd_config.d ..."
mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/99-hardening.conf <<CONF
# Managed by MicroOS bootstrap script
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

PermitRootLogin no
AllowGroups ${SSH_GROUP}

AuthorizedKeysFile .ssh/authorized_keys

MaxAuthTries 3
LoginGraceTime 20
CONF
chmod 0644 /etc/ssh/sshd_config.d/99-hardening.conf

# Seed /etc/ssh/sshd_config if missing (some images keep canonical config in /usr/etc)
if [[ ! -f /etc/ssh/sshd_config ]]; then
  if [[ -f /usr/etc/ssh/sshd_config ]]; then
    mkdir -p /etc/ssh
    cp /usr/etc/ssh/sshd_config /etc/ssh/sshd_config
  elif [[ -f /etc/ssh/sshd_config.default ]]; then
    mkdir -p /etc/ssh
    cp /etc/ssh/sshd_config.default /etc/ssh/sshd_config
  fi
fi

# --------------------------------------------------------------------------
# fail2ban configuration
# --------------------------------------------------------------------------
echo "==> Configuring fail2ban for SSH..."
install -d /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled  = true
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5
JAIL

# --------------------------------------------------------------------------
# syslog-ng forwarding + disk buffering
# --------------------------------------------------------------------------
echo "==> Configuring syslog-ng forwarding with disk buffering..."
install -d /etc/syslog-ng/conf.d
install -d -m 0755 "${SYSLOG_BUFFER_DIR}"

cat >/etc/syslog-ng/conf.d/99-forward-all.conf <<CONF
destination d_remote_tcp {
  syslog("${SYSLOG_HOST}"
    transport("tcp")
    port(${SYSLOG_PORT})
    flags(syslog-protocol)
    time-reopen(10)
    disk-buffer(
      reliable(${SYSLOG_DISKBUF_RELIABLE})
      disk-buf-size(${SYSLOG_DISKBUF_SIZE})
      qfile("${SYSLOG_BUFFER_FILE}")
    )
  );
};

log { source(src); destination(d_remote_tcp); };
CONF

# --------------------------------------------------------------------------
# First-boot oneshot: create home + keys ON LIVE SYSTEM (after reboot)
# --------------------------------------------------------------------------
echo "==> Installing first-boot oneshot to create home + authorized_keys on live system..."
install -d /etc/microos-bootstrap

cat >/etc/microos-bootstrap/firstboot-homekeys.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="darren"
SSH_GROUP="ssh-users"
GITHUB_USER="soothill"

# Source of truth for sshd chdir:
USER_HOME="$(getent passwd "${USER_NAME}" | awk -F: '{print $6}')"
if [[ -z "${USER_HOME}" ]]; then
  echo "ERROR: Could not determine home directory for ${USER_NAME} from passwd."
  exit 1
fi

getent group "${SSH_GROUP}" >/dev/null 2>&1 || groupadd "${SSH_GROUP}"
id -u "${USER_NAME}" >/dev/null 2>&1 || useradd -M -s /bin/bash "${USER_NAME}"

# Create home on LIVE filesystem (important when /home is a separate mount)
mkdir -p "${USER_HOME}"
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}"
chmod 0750 "${USER_HOME}"

# Enforce ONLY darren in ssh-users
usermod -aG "${SSH_GROUP}" "${USER_NAME}" || true
gpasswd -M "${USER_NAME}" "${SSH_GROUP}"

# Install keys
install -d -m 0700 -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.ssh"
curl -fsSL "https://github.com/${GITHUB_USER}.keys" -o "${USER_HOME}/.ssh/authorized_keys"
chown "${USER_NAME}:${USER_NAME}" "${USER_HOME}/.ssh/authorized_keys"
chmod 0600 "${USER_HOME}/.ssh/authorized_keys"

systemctl try-restart sshd >/dev/null 2>&1 || true
SCRIPT

chmod 0755 /etc/microos-bootstrap/firstboot-homekeys.sh

cat >/etc/systemd/system/microos-firstboot-homekeys.service <<'UNIT'
[Unit]
Description=MicroOS first boot: create home directory and install GitHub authorized_keys
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/microos-bootstrap/firstboot-homekeys.sh
ExecStartPost=/usr/bin/systemctl disable microos-firstboot-homekeys.service
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable microos-firstboot-homekeys.service

# --------------------------------------------------------------------------
# Tailscale performance tuning (persistent) using /etc/tailscale/ script
# Fixes 203/EXEC issues seen with /usr/local on some MicroOS layouts.
# --------------------------------------------------------------------------
echo "==> Installing Tailscale ethtool performance tuning (persistent)..."
install -d /etc/tailscale

cat >/etc/tailscale/tailscale-ethtool-tune.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Determine default route interface (matches Tailscale KB best practice intent)
NETDEV="$(ip -o route get 8.8.8.8 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

if [[ -z "${NETDEV}" ]]; then
  echo "tailscale-ethtool: could not determine default-route interface; skipping."
  exit 0
fi

if ! command -v ethtool >/dev/null 2>&1; then
  echo "tailscale-ethtool: ethtool not installed; skipping."
  exit 0
fi

# Apply only if supported by NIC driver
if ethtool -k "${NETDEV}" 2>/dev/null | grep -qE 'rx-udp-gro-forwarding:'; then
  ethtool -K "${NETDEV}" rx-udp-gro-forwarding on rx-gro-list off || true
  echo "tailscale-ethtool: applied tuning on ${NETDEV}"
else
  echo "tailscale-ethtool: ${NETDEV} does not support rx-udp-gro-forwarding; skipping."
fi

exit 0
SCRIPT

chmod 0755 /etc/tailscale/tailscale-ethtool-tune.sh

cat >/etc/systemd/system/tailscale-ethtool.service <<'UNIT'
[Unit]
Description=Tailscale performance tuning (ethtool GRO settings)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/tailscale/tailscale-ethtool-tune.sh

[Install]
WantedBy=multi-user.target
UNIT

systemctl enable tailscale-ethtool.service

# --------------------------------------------------------------------------
# Enable services
# --------------------------------------------------------------------------
echo "==> Enabling services..."
systemctl enable sshd tailscaled syslog-ng fail2ban

# Optional: unattended Tailscale enrollment
if [[ -n "${TS_AUTHKEY:-}" ]]; then
  echo "==> Attempting unattended Tailscale enrollment..."
  tailscale up --authkey="${TS_AUTHKEY}" --accept-dns=false || true
fi

echo "==> Snapshot configuration complete."
EOF

if [[ "${AUTO_REBOOT}" == "1" ]]; then
  log "Rebooting to activate new snapshot..."
  transactional-update reboot
else
  log "Snapshot ready. Reboot manually when convenient: sudo transactional-update reboot"
fi
