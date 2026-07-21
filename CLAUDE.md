# nix-config — wheezertbts homelab
NixOS 26.05 flake for the household homelab server. Live box; roommates depend on it.

## Hard rules
- Never disable openssh / remove authorized keys / close port 22.
- Never break Headscale (apex vhost wheezertbts.duckdns.org → :8080, ports 80/443, DuckDNS timer).
- Secrets via agenix only; *File/environmentFile options, never inline.
- Build → test → switch; verify a fresh ssh session after network/firewall changes.
- Don't restructure /mnt/media data without explicit approval.

## Commands
- Rebuild: sudo nixos-rebuild switch --flake .#wheezertbts
- Safe try: sudo nixos-rebuild test --flake .#wheezertbts
- Rollback: sudo nixos-rebuild switch --rollback
- Secret edit (run from the secrets dir — the CLI resolves rules relative to cwd):
  cd hosts/wheezertbts/secrets
  on the server (FILE must come right after -e, and sudo may drop $EDITOR):
    sudo EDITOR=nano agenix -e <name>.age -i /etc/ssh/ssh_host_ed25519_key
  on the desktop (corbi key): agenix -e <name>.age
  Keep the DUCKDNS_TOKEN=... env format when editing duckdns-token.age.

## Map
- hosts/wheezertbts/ — machine config + secrets
- modules/homelab/ — options + service modules (homelab.services.<name>)
- Plan & rationale: claude-code-homelab-plan.md / service-plan.md (Claude project)

## Current phase note
Phase 5 complete: arr stack (prowlarr/sonarr/radarr/jellyseerr — upstream
module is services.seerr) behind internal vhosts; qBittorrent confined to
the wg_client netns (Surfshark WireGuard us-dal, surfshark-wg.age in
`wg setconf` format — Endpoint by IP, no Address/DNS lines; those are
module options privateIP/dnsIPs). Kill switch verified: netns egress =
Surfshark IP, wg0 only default route, netns dark when wg_client.service
stops. WebUI via socket proxy on host 127.0.0.1:8081 -> qbt.<domain>.
qBittorrent's qBittorrent.conf is deliberately NOT nix-managed
(serverConfig would clobber UI-set admin password on every start).
OpenVPN surfshark retired. AdGuard web UI + qBittorrent WebUI still
need passwords set in their UIs; arr interconnect wizards pending.
Next: Phase 6 (household apps).
