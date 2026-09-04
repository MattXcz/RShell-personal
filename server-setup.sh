#!/bin/bash
# One-shot installer for the HOME SERVER side.
# Run as root, either interactively:
#
#   sudo ./server-setup.sh
#
# or non-interactively (e.g. piped from curl, key passed as $1):
#
#   curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/server-setup.sh \
#     | sudo REMOTE_PORT=2222 bash -s -- "ssh-ed25519 AAAA... router-reverse-tunnel"
#
# Sets up a restricted account that the router uses ONLY to open the reverse
# tunnel. This account cannot get a shell, run commands, or forward
# anywhere except back to itself on REMOTE_PORT.
set -euo pipefail

TUNNEL_USER="${TUNNEL_USER:-routertunnel}"
REMOTE_PORT="${REMOTE_PORT:-2222}"
ROUTER_PUBKEY="${1:-}"

if [ -z "$ROUTER_PUBKEY" ]; then
  echo "Paste the router's PUBLIC key (from install-router.sh output) and press Enter:"
  read -r ROUTER_PUBKEY
fi

if [ -z "$ROUTER_PUBKEY" ]; then
  echo "No public key provided, aborting." >&2
  exit 1
fi

# 1. Create the restricted user with no login shell
if ! id "$TUNNEL_USER" >/dev/null 2>&1; then
  useradd -r -m -d "/home/${TUNNEL_USER}" -s /usr/sbin/nologin "$TUNNEL_USER"
fi

mkdir -p "/home/${TUNNEL_USER}/.ssh"
chmod 700 "/home/${TUNNEL_USER}/.ssh"

AUTHORIZED_KEYS="/home/${TUNNEL_USER}/.ssh/authorized_keys"
# Restrict this key to: no shell, no pty, no X11/agent forwarding,
# and only allowed to bind the single tunnel port on localhost.
echo "restrict,port-forwarding,permitlisten=\"127.0.0.1:${REMOTE_PORT}\" ${ROUTER_PUBKEY}" > "$AUTHORIZED_KEYS"

chmod 600 "$AUTHORIZED_KEYS"
chown -R "${TUNNEL_USER}:${TUNNEL_USER}" "/home/${TUNNEL_USER}/.ssh"

# 2. Make sure sshd allows TCP forwarding globally (needed for reverse tunnels),
# GatewayPorts stays "no" so the forwarded port is only reachable from
# localhost on the server itself, not from the internet.
SSHD_CONFIG="/etc/ssh/sshd_config"
grep -q '^AllowTcpForwarding' "$SSHD_CONFIG" || echo "AllowTcpForwarding yes" >> "$SSHD_CONFIG"
grep -q '^GatewayPorts' "$SSHD_CONFIG" || echo "GatewayPorts no" >> "$SSHD_CONFIG"

systemctl restart sshd

cat <<EOF

Done. Once the router's tunnel is up, connect to the router from THIS server with:

    ssh -p ${REMOTE_PORT} root@127.0.0.1

(use the router's own root/admin credentials there - that login is completely
separate from the '${TUNNEL_USER}' account used for the tunnel).

Recommended hardening:
  - Change REMOTE_PORT to something non-obvious.
  - Put fail2ban in front of sshd on the home server.
  - Keep sshd on the home server key-auth only (PasswordAuthentication no).
  - Only expose the home server's SSH port to the internet if you actually
    need to reach it remotely; otherwise keep it LAN/VPN-only and rely on
    this tunnel purely for router recovery when you're on the same network
    or connect to the home server via its own VPN.
EOF
