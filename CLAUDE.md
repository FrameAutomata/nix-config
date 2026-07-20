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
- Secret edit: agenix -e hosts/wheezertbts/secrets/<name>.age

## Map
- hosts/wheezertbts/ — machine config + secrets
- modules/homelab/ — options + service modules (homelab.services.<name>)
- Plan & rationale: claude-code-homelab-plan.md / service-plan.md (Claude project)

## Current phase note
Phase 2 complete: agenix live; duckdns-token.age decrypts via the host ssh
key, DuckDNS unit reads it as an EnvironmentFile.
Next: Phase 3 (wildcard cert via DNS-01 + internal nginx vhost layer).
