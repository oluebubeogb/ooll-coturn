#!/bin/sh
# Generate turnserver.conf from environment and start coturn.
set -eu

CONF="/tmp/turnserver.conf"
: "${TURN_REALM:=turn.example.com}"
: "${TURN_USERNAME:=oollspace}"
: "${LISTEN_PORT:=3478}"
: "${TLS_PORT:=5349}"
: "${MIN_PORT:=49152}"
: "${MAX_PORT:=49999}"
: "${USER_QUOTA:=12}"
: "${TOTAL_QUOTA:=1200}"
: "${TURN_CERT:=/certs/fullchain.pem}"
: "${TURN_KEY:=/certs/privkey.pem}"

if [ -z "${TURN_PASSWORD:-}" ]; then
  echo "TURN_PASSWORD is required. Set it in Coolify / .env and redeploy." >&2
  exit 1
fi

EXTERNAL_IP="${EXTERNAL_IP:-}"
if [ -z "$EXTERNAL_IP" ]; then
  # Best-effort public IPv4. Set EXTERNAL_IP explicitly when this fails
  # (for example a VPS behind 1:1 NAT — use public, or public/private).
  DETECTED=""
  if command -v curl >/dev/null 2>&1; then
    DETECTED=$(curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)
  fi
  if [ -z "$DETECTED" ] && command -v wget >/dev/null 2>&1; then
    DETECTED=$(wget -q -O- --timeout=4 https://api.ipify.org 2>/dev/null || true)
  fi
  if [ -n "$DETECTED" ]; then
    EXTERNAL_IP="$DETECTED"
    echo "Auto-detected EXTERNAL_IP=${EXTERNAL_IP}" >&2
  else
    echo "WARNING: EXTERNAL_IP is empty and auto-detect failed. Coturn will advertise the listening address; set EXTERNAL_IP if clients cannot connect." >&2
  fi
fi

TLS_ON=0
if [ -n "${TURN_CERT}" ] && [ -n "${TURN_KEY}" ] && [ -f "$TURN_CERT" ] && [ -f "$TURN_KEY" ]; then
  TLS_ON=1
  echo "TLS certificates found — TURNS enabled on port ${TLS_PORT}." >&2
else
  echo "No TLS cert/key at ${TURN_CERT} / ${TURN_KEY}; TURNS is off. Mount certs and set TURN_CERT / TURN_KEY to enable it." >&2
fi

umask 077
cat > "$CONF" <<CFG
# Generated at container start — do not edit.
listening-port=${LISTEN_PORT}
tls-listening-port=${TLS_PORT}
min-port=${MIN_PORT}
max-port=${MAX_PORT}
listening-ip=0.0.0.0
CFG

if [ -n "$EXTERNAL_IP" ]; then
  echo "external-ip=${EXTERNAL_IP}" >> "$CONF"
fi

cat >> "$CONF" <<CFG
realm=${TURN_REALM}
server-name=${TURN_REALM}
lt-cred-mech
user=${TURN_USERNAME}:${TURN_PASSWORD}
fingerprint
no-cli
no-multicast-peers
stale-nonce=600
mobility
user-quota=${USER_QUOTA}
total-quota=${TOTAL_QUOTA}
log-file=stdout
simple-log
verbose
no-tlsv1
no-tlsv1_1
# Deny relay to private, loopback, link-local and documentation ranges (SSRF / relay abuse).
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.0.0.0-192.0.0.255
denied-peer-ip=192.0.2.0-192.0.2.255
denied-peer-ip=192.88.99.0-192.88.99.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=198.18.0.0-198.19.255.255
denied-peer-ip=198.51.100.0-198.51.100.255
denied-peer-ip=203.0.113.0-203.0.113.255
denied-peer-ip=224.0.0.0-239.255.255.255
denied-peer-ip=240.0.0.0-255.255.255.255
denied-peer-ip=::1
denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
CFG

if [ "$TLS_ON" -eq 1 ]; then
  echo "cert=${TURN_CERT}" >> "$CONF"
  echo "pkey=${TURN_KEY}" >> "$CONF"
else
  echo "no-tls" >> "$CONF"
  echo "no-dtls" >> "$CONF"
fi

exec turnserver -c "$CONF" --pidfile /var/tmp/turnserver.pid
