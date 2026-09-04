#!/bin/sh
# One-shot installer for the router side of the reverse SSH tunnel.
# Run on the ROUTER as root - only the home server address is required:
#
#   curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/install-router.sh \
#     | sh -s -- your.home.server
#
# HOME_SERVER_PORT/REMOTE_PORT/TUNNEL_USER can still be overridden via env
# vars if your setup differs from the defaults below.
#
# Idempotent: safe to re-run (keeps existing key, just refreshes the service).
set -e

HOME_SERVER_HOST="${HOME_SERVER_HOST:-${1:?usage: install-router.sh <home-server-address>}}"
HOME_SERVER_PORT="${HOME_SERVER_PORT:-2222}"
REMOTE_PORT="${REMOTE_PORT:-2222}"
TUNNEL_USER="${TUNNEL_USER:-routertunnel}"
KEY="/root/.ssh/tunnel_id_ed25519"

command -v ssh >/dev/null 2>&1 || { echo "openssh client ('ssh') not found on this router" >&2; exit 1; }

mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -f "$KEY" -N '' -C router-reverse-tunnel
  echo "Generated new tunnel key: ${KEY}"
else
  echo "Reusing existing tunnel key: ${KEY}"
fi

if command -v systemctl >/dev/null 2>&1; then
  cat > /etc/systemd/system/router-tunnel.service <<EOF
[Unit]
Description=Reverse SSH tunnel to home server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -i ${KEY} -N \\
  -o ExitOnForwardFailure=yes \\
  -o ServerAliveInterval=15 \\
  -o ServerAliveCountMax=3 \\
  -o StrictHostKeyChecking=accept-new \\
  -o BatchMode=yes \\
  -R 127.0.0.1:${REMOTE_PORT}:127.0.0.1:22 \\
  -p ${HOME_SERVER_PORT} ${TUNNEL_USER}@${HOME_SERVER_HOST}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now router-tunnel.service
  echo "Installed and started router-tunnel.service (systemd)."
else
  cat > /root/router-watchdog.sh <<EOF
#!/bin/sh
PIDFILE=/var/run/router-tunnel.pid
[ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null && exit 0
ssh -i ${KEY} -N \\
  -o ExitOnForwardFailure=yes \\
  -o ServerAliveInterval=15 \\
  -o ServerAliveCountMax=3 \\
  -o StrictHostKeyChecking=accept-new \\
  -o BatchMode=yes \\
  -R 127.0.0.1:${REMOTE_PORT}:127.0.0.1:22 \\
  -p ${HOME_SERVER_PORT} ${TUNNEL_USER}@${HOME_SERVER_HOST} &
echo \$! > "\$PIDFILE"
EOF
  chmod +x /root/router-watchdog.sh
  ( crontab -l 2>/dev/null | grep -v router-watchdog.sh ; echo "* * * * * /root/router-watchdog.sh >/dev/null 2>&1" ) | crontab -
  echo "Installed cron watchdog (no systemd found)."
fi

echo
echo "=================================================================="
echo "Router side done. Now run this ONE command on your HOME SERVER"
echo "(needs a machine that can already reach it, e.g. over LAN/SSH):"
echo
echo "  curl -fsSL https://raw.githubusercontent.com/MattXcz/RShell-personal/main/server-setup.sh \\"
echo "    | sudo REMOTE_PORT=${REMOTE_PORT} bash -s -- \"$(cat ${KEY}.pub)\""
echo "=================================================================="
