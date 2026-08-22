# nix-config

NixOS flake for the `wheezertbts` household homelab server and the
`frame-automata` desktop that administers it.

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
sudo nixos-rebuild switch --flake .#frame-automata   # the desktop
sudo nixos-rebuild switch --rollback             # undo
```

## Structure

- `hosts/wheezertbts/` — server config + agenix secrets
- `hosts/frame-automata/` — desktop config; holds the `admin` key that edits
  those secrets, so it is the recovery path if the server host key rotates
- `modules/common/` — host-agnostic base (locale, nix settings, ssh, gpu)
- `modules/workstation/` — interactive base: Plasma, audio, gaming, nix gc
- `modules/homelab-client/` — the *using* side: tailnet, ntfy alerts, mounts
- `modules/notify.nix` — ntfy failure alerts, shared by server and clients
- `site.nix` — facts both sides need (domain, LAN IP, topic, timezone)
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

## Desktop (`frame-automata`)

Separate `nixpkgs-desktop` input: the server's `nixpkgs` pin exists for server
reasons and must not gate a workstation. Update one without the other:

```sh
nix flake update nixpkgs-desktop    # desktop only
nix flake update nixpkgs            # server only
```

It auto-upgrades weekly from `github:FrameAutomata/nix-config#frame-automata`,
so deploying is pushing and the running system always matches a commit.

### First boot — none of this is declarative

**1. Hardware scan.** `hosts/frame-automata/hardware-configuration.nix` is a
`throw` placeholder. Generate it, then **commit and push** — `system.autoUpgrade`
builds from `github:FrameAutomata/nix-config`, so an uncommitted scan means a
local rebuild works while every weekly upgrade dies on the placeholder. It also
keeps `nix flake check` red for the whole repo.

```sh
nixos-generate-config --show-hardware-config > hosts/frame-automata/hardware-configuration.nix
```

**2. A password for `frame-automata`.** The account sets none of
`hashedPassword`/`hashedPasswordFile`/`initialPassword` (a public repo is no
place for either of the first two), so a fresh install leaves it locked and SDDM
rejects every password. From a root TTY:

```sh
passwd frame-automata
```

**3. Join the tailnet.** There is deliberately no `authKeyFile` — pre-auth keys
expire in 24h. Mint one on the server (`headscale preauthkeys create`), then:

```sh
sudo tailscale up --login-server https://wheezertbts.duckdns.org --auth-key <key> --accept-routes
```

**4. The Samba login.** Not agenix: this host holds the `admin` key, not a host
key in `secrets.nix`, so it cannot decrypt. Enroll its
`/etc/ssh/ssh_host_ed25519_key.pub` in `keys.nix` after first boot to fix that
properly. Until then, set the password on the server with
`sudo smbpasswd -a wheezertbts`, then:

```sh
sudo install -m 0600 -D /dev/null /etc/samba/credentials-homelab
sudo tee /etc/samba/credentials-homelab >/dev/null <<'EOF'
username=wheezertbts
password=<the smbpasswd password>
EOF
```

Shares mount on demand under `/mnt/homelab/`; a missing credentials file shows
up as a mount error on first access, not at build time.
