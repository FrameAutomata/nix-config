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
  on the server: sudo agenix -e -i /etc/ssh/ssh_host_ed25519_key <name>.age
  on the desktop (corbi key): agenix -e <name>.age
  Keep the DUCKDNS_TOKEN=... env format when editing duckdns-token.age.

## Map
- hosts/wheezertbts/ — machine config + secrets
- modules/homelab/ — options + service modules (homelab.services.<name>)
- Plan & rationale: claude-code-homelab-plan.md / service-plan.md (Claude project)

## Current phase note
Phase 4 complete: AdGuard Home on :53 (LAN + tailnet), split-DNS rewrites
*.baseDomain -> lanIP, tailnet clients resolve via headscale global
nameserver = this box's tailnet IP (homelab.tailnetIP), LAN subnet
advertised to the tailnet. The HOST itself stays on public upstreams
(bootstrap-deadlock avoidance) + an extraHosts apex pin (its own tailscale
client must not depend on hairpin NAT). AdGuard web UI (adguard.<domain>)
has NO auth until Thomas sets a password in the UI.
Next: Phase 5 (download stack in a WireGuard netns).
