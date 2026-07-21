# nix-config

NixOS flake for the `wheezertbts` household homelab server.

**Status:** Phase 7 — safety net live: hourly btrbk snapshots of the media
pool, nightly restic backups of service state to a local repo on the
mirror (B2 offsite ready, pending credentials), Scrutiny SMART monitoring,
and ntfy failure alerts. On top of the earlier phases: household apps +
privacy model, VPN-confined download stack, AdGuard split DNS, wildcard
TLS + internal vhosts, agenix, flake + module skeleton.

## Rebuild

```sh
sudo nixos-rebuild build --flake .#wheezertbts   # dry build
sudo nixos-rebuild test --flake .#wheezertbts    # apply without making it the boot default
sudo nixos-rebuild switch --flake .#wheezertbts
sudo nixos-rebuild switch --rollback             # undo
```

## Structure

- `hosts/wheezertbts/` — machine config + agenix secrets
- `modules/common/` — host-agnostic base (locale, nix settings, ssh, nvidia)
- `modules/homelab/` — `homelab.*` options and service modules
  (`homelab.services.<name>`); services register their reverse-proxy vhost
  in `homelab.nginx.internal`, whose optional `dashboard` field doubles as
  the Homepage tile registry

## Household storage & privacy model

Three tiers on `/mnt/media` (`modules/homelab/household.nix`; the admin is
always a member, roommates are listed as agreed handles in
`homelab.household.members` — real names stay out of this public repo):

1. **`Private/<name>`** — one per member, mode `2770 <name>:<name>`, plus a
   non-browseable Samba share `[<name>]` restricted to that member. Samba
   auth and filesystem permissions each *independently* deny other members;
   `Private/` itself is `0711` and both household areas are vetoed out of
   the `[media]` share, so each area is reachable only through its own
   properly-scoped share.
2. **`Shared`** — communal drop zone, group `household`, mode `2775`,
   Samba share `[shared]`.
3. **`[media]`** — the media library, communal by design.

Member accounts have no shell; they exist for Samba and file ownership.
Samba passwords are manual: `sudo smbpasswd -a <name>`. FileBrowser serves
`/mnt/media` through per-account jails configured in its admin UI — **set a
member's scope to their `Private/<name>` before handing out credentials**
(a new FileBrowser account defaults to the whole root); its daemon user
sits in each personal group for that reason, which is why the app-layer
jail is the only member-vs-member barrier on the FileBrowser path.

**The honest admin caveat:** root on this box can technically read
everything on it *except* Vaultwarden vaults, which are end-to-end
encrypted. Backups (Phase 7) include private areas only opt-in, but
filesystem snapshots cover everything and retain deleted files for the
retention window. Anyone wanting admin-proof privacy should layer
client-side encryption (e.g. Cryptomator) over their private share.

## Credits

Module patterns (wireguard-netns, socket-proxy, the `homelab.services.*`
option layout) are adapted from
[notthebee's nix-config](https://git.notthebe.ee/notthebee/nix-config) (MIT).
