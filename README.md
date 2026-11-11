# OOLL Space coturn

A standalone [coturn](https://github.com/coturn/coturn) TURN/STUN relay for **OOLL Space** WebRTC apps (voice and video calls). Any project can share it; give each its own username and password.

Run it as its **own git repo and Coolify project**, not inside any app's compose file. Host networking is required so the UDP relay port range is reachable. Coolify supports `network_mode: host`.

Traefik (and Coolify’s HTTP proxy) **cannot proxy UDP**. Do not put this service behind the proxy. Clients must reach the host’s public IP or DNS name (for example `turn.example.com`) directly on the ports below.

## What it is

WebRTC needs STUN to discover public addresses, and **TURN** to relay audio when a direct peer connection is blocked (symmetric NAT, strict firewalls). This project runs the official `coturn/coturn` image, generates `turnserver.conf` from environment variables at start, and uses long-term credentials (`lt-cred-mech`).

## Ports to open on the firewall

| Port | Protocol | Purpose |
| --- | --- | --- |
| `3478` | TCP and UDP | TURN/STUN (`LISTEN_PORT`) |
| `5349` | TCP | TURNS / TLS (`TLS_PORT`), if certificates are mounted |
| `49152–49999` | UDP | Media relay range (`MIN_PORT`–`MAX_PORT`) |

The relay range is intentionally smaller than the full IANA ephemeral range. Change the bounds with `MIN_PORT` / `MAX_PORT` if you need a different window, and open the same range on the firewall.

## Coolify steps

1. Push this repository to git (GitHub, GitLab, or a Coolify-managed repo).
2. In Coolify: **New Project** → **Add Resource** → **Docker Compose** (from that git repo).
3. Set the environment variables listed in `.env.example` (at least `TURN_REALM`, `TURN_USERNAME`, and `TURN_PASSWORD`). Leave `EXTERNAL_IP` blank to auto-detect, or set the public IPv4 (or `public/private` if the host is behind 1:1 NAT).
4. Do **not** enable the HTTP proxy / Traefik for this resource. Host networking already binds the TURN ports on the server.
5. Deploy. Check the container logs for “Auto-detected EXTERNAL_IP=…” or set `EXTERNAL_IP` if that warning appears.
6. Point a DNS A record such as `turn.example.com` at the server if you want a hostname (required for a proper TURNS certificate).

Locally, the same compose file works:

```bash
cp .env.example .env
# edit TURN_PASSWORD (and usually TURN_REALM)
docker compose up -d
```

## TLS for TURNS (`turns:` URIs)

1. Issue a certificate for the TURN hostname (for example `turn.example.com`) with Let’s Encrypt, Coolify’s certificate tools, or any ACME client. This is a **direct TLS listener on 5349**, not an HTTPS site behind Traefik.
2. Place `fullchain.pem` and `privkey.pem` in a directory and mount it at `/certs` (the default volume is `./certs`, overridable with `TURN_CERT_DIR`).
3. Optionally set `TURN_CERT=/certs/fullchain.pem` and `TURN_KEY=/certs/privkey.pem` if you use different filenames.
4. Restart the service. Logs should say that TURNS is enabled. If the files are missing, TLS is disabled and only `turn:` (3478) is offered.

## Values to set in your app

In each app's environment (Coolify or `.env`):

```bash
TURN_URL=turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp,turns:turn.example.com:5349?transport=tcp
TURN_USERNAME=oollspace
TURN_CREDENTIAL=the-same-password-as-TURN_PASSWORD
```

- `TURN_URL` is comma-separated. Include UDP, TCP, and (when TLS is on) TURNS. Replace `turn.example.com` with your hostname or public IP (IPs cannot use a trusted `turns:` certificate).
- `TURN_USERNAME` must match `TURN_USERNAME` here.
- `TURN_CREDENTIAL` must match `TURN_PASSWORD` here.

Variable names may differ per app; use whatever your app expects for its TURN URL, username and credential.

## How to test

1. Open [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/).
2. Add a STUN server if you want (`stun:turn.example.com:3478`), and a TURN server:
   - URI: `turn:turn.example.com:3478?transport=udp` (also try `?transport=tcp` and `turns:turn.example.com:5349?transport=tcp`)
   - Username / password: the values above
3. Gather candidates. You should see at least one candidate with type **`relay`**. If you only see `host` or `srflx`, the relay ports or `EXTERNAL_IP` are probably wrong, or the firewall is still closed.

## Hardening (already in the generated config)

- Long-term credentials (`lt-cred-mech`) and `fingerprint`
- `no-cli`, `no-multicast-peers`
- `denied-peer-ip` for RFC1918, loopback, link-local, CGNAT, multicast, and documentation ranges — prevents the relay from being used for SSRF against private networks
- `user-quota` / `total-quota`, `stale-nonce`, `mobility`
- Logs to stdout
- TLS 1.0/1.1 disabled when certificates are present
- TCP and UDP allocations are both allowed so clients can fall back to TCP TURN when UDP is blocked

## Environment reference

See `.env.example` for the full list and comments. No real secrets belong in git.
