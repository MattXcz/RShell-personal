#!/bin/sh
# Reverse SSH tunnel watchdog for the router side.
# Keeps an outbound tunnel to the home server alive independently of the VPN,
# so the home server can always SSH back into this router.
#
# Deploy: copy to the router, chmod +x, and run every minute from cron:
#   * * * * * /root/router-watchdog.sh >/dev/null 2>&1
#
# Requires: ssh client on the router (openssh-client or dropbear with -R support)
# and a private key at $KEY that is authorized (restricted, see server setup)
# on the home server.

# --- configure these ---
HOME_SERVER_HOST="your.home.server"      # public hostname/IP of your home server
HOME_SERVER_PORT="22"                    # SSH port the home server listens on
TUNNEL_USER="routertunnel"               # restricted user created on the home server
REMOTE_PORT="2222"                       # port opened on the home server's localhost, forwards to router:22
LOCAL_SSH_PORT="22"                      # router's own sshd port
KEY="/root/.ssh/tunnel_id_ed25519"       # private key dedicated to this tunnel
PIDFILE="/var/run/router-tunnel.pid"
# ------------------------

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

if is_running; then
  exit 0
fi

ssh -i "$KEY" \
    -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    -R "127.0.0.1:${REMOTE_PORT}:127.0.0.1:${LOCAL_SSH_PORT}" \
    -p "$HOME_SERVER_PORT" \
    "${TUNNEL_USER}@${HOME_SERVER_HOST}" &

echo $! > "$PIDFILE"
