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
Phase 7 complete: btrbk hourly snapshots of the pool root (subvolume ".",
ladder 24h/7d/4w) into /mnt/media/.snapshots; restic nightly (04:15) to
the local repo /mnt/media/Backups/restic (its own subvolume so snapshots
don't pin repo blocks) — sqlite-heavy services stop-copy-start via
prepare/cleanup (cleanup is postStop, runs even on failure); adguardhome +
headscale stay up (live-copied). DynamicUser state paths must be the
/var/lib/private/* REAL paths (restic stores symlinks as symlinks):
prowlarr, seerr, uptime-kuma, AdGuardHome. Restore verified end-to-end
(restic-local dump + diff). B2 offsite: backup.b2 sub-options ready,
waiting on Thomas's bucket + key -> b2-env.age. Scrutiny at disks. (port
8085; pulls in influxdb2 — watch RAM). ntfy at ntfy. with
homelab-notify@ OnFailure hooks: restic, btrbk, duckdns, scrub, and BOTH
acme unit families (acme-<cert> AND acme-order-renew-<cert> — the timers
trigger the latter). Verified: failure push arrives on topic "homelab".
Onboarding of ALL users deliberately deferred to the end (Thomas's call).

Phase 6 complete: Vaultwarden (vault., signups OPEN until roommates
register — then flip homelab.services.vaultwarden.allowSignups off),
Navidrome (music., library /mnt/media/Music — there is no Media/ parent
dir), FileBrowser (files., root /mnt/media, per-account jails are UI
state: ALWAYS scope an account before handing out credentials), Homepage
(home., tiles ride the `dashboard` field on homelab.nginx.internal
entries), Uptime Kuma (status., monitors pending in its UI — internal
vhost names resolve locally via the nginx.nix extraHosts pins). Household
model live: homelab.household.enable, members = roommate handles only
(admin auto-included, handles validated against reserved names);
Private/<name> 2770 + per-person share, Shared 2775 @household, [media]
vetoes /Private/Shared/. Samba shares go through the
homelab.services.samba.shares registry. FileBrowser runs UMask 0002 +
StateDirectoryMode 0700 (Bolt DB holds the JWT signing secret); its
upstream tmpfiles rule set is mkForce-replaced so /mnt/media stays
unmanaged. Pending manual (§8): smbpasswd -a per member, roommate web-UI
accounts, FileBrowser jails, Kuma monitors, AdGuard/qBittorrent UI
passwords, arr interconnect wizards. Next: Phase 7 (btrbk, restic→B2,
Scrutiny, ntfy).
