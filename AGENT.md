# AGENT.md

This repository uses `AGENTS.md` as the canonical agent guide. Follow those instructions when working here.

Quick reminders:

- The repo manages DynDNS updates plus Cloudflare/nginx subdomain provisioning.
- Cloudflare is the primary provider path; Strato is legacy.
- Cloudflare config is `.env` first, with `cloudflare-dyndns.conf` as a legacy fallback.
- Strato config lives in `strato-dyndns.conf`.
- Never commit real credentials from `.env`, `cloudflare-dyndns.conf`, or `strato-dyndns.conf`. Do not echo those files to chat or stdout either — redact with `grep -v` / `sed`, or source them in a subshell.
- Install flows are `sudo bash install-cloudflare.sh` and `sudo bash install.sh`.
- Keep shell, systemd, and nginx changes small and consistent with the existing deployment model.
