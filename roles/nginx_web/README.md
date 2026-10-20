# nginx_web — Self-Healing Demo Workload

nginx serving one page and a `/healthz` endpoint: the service the self-healing lab watches, breaks and heals. Small on purpose, but production-shaped: the Debian default site is replaced, every configuration change is tested with `nginx -t` before nginx reloads, and the port is opened in ufw only for the listed sources.

| | |
|---|---|
| **Target** | Ubuntu 26.04 LTS · Ubuntu 24.04 LTS |
| **Requires** | ansible-core ≥ 2.16 · community.general (ufw) |
| **Playbook** | `playbooks/selfheal_target.yml` · Ascender job template **Self-Heal - Deploy target** |
| **Validated** | Ubuntu 26.04.1 LTS with the CIS L1 baseline · nginx 1.28.3 |

---

## 1. What the role changes

| Item | Change |
|---|---|
| Package | `nginx` (Ubuntu archive) |
| Site | `/etc/nginx/sites-available/selfheal-lab` (enabled), default site disabled; `server_tokens off` and two security headers at server level |
| `/healthz` | `200 ok`, no access log: used by the remediation verification (`health_url`) |
| Page | `/var/www/html/index.html` (shows the inventory host name) |
| Firewall | `allow <port>/tcp from <source>` for each `nginx_web_allow_from` entry, only if ufw is installed |

> **CIS exception.** CIS L1 recommends no web server on a server that does not need one. On `selfheal_targets` nginx *is* the workload, so this is a documented exception.

## 2. Variables

All in [`defaults/main.yml`](defaults/main.yml).

| Variable | Default | Purpose |
|---|---|---|
| `nginx_web_port` | `80` | Listen port (IPv4 and IPv6). |
| `nginx_web_allow_from` | `[]` (lab: `10.0.2.2/32`) | Sources allowed through ufw. Empty = local only. |
| `nginx_web_title` | `Self-healing lab` | Page title. |

## 3. Role files

| File | Purpose |
|---|---|
| [`tasks/main.yml`](tasks/main.yml) | Package, site, page, firewall, service, health check. |
| [`handlers/main.yml`](handlers/main.yml) | `nginx -t`, then reload. |
| [`templates/`](templates/) | Site configuration and demo page. |

Architecture: [Figure 3 of the main README](../../README.md#81-architecture).
