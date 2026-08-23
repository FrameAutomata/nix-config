# nix-config

NixOS flake for the `wheezertbts` household homelab server, the `frame-automata`
desktop that administers it, and the `frame-automobile` laptop.

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
sudo nixos-rebuild switch --flake .#frame-automobile # the laptop
sudo nixos-rebuild switch --rollback             # undo
```

## Structure

- `hosts/wheezertbts/` — server config + its agenix secrets
- `hosts/frame-automata/` — desktop config + its own agenix secrets; also holds
  the `admin` key that edits *both* sets, so it is the recovery path if either
  host key rotates
- `hosts/frame-automobile/` — laptop config; no secrets and no key in `keys.nix`
- `modules/common/` — host-agnostic base (locale, nix settings, ssh, gpu;
  `amdgpu.nix` and `intel-gpu.nix` are opt-in per host)
- `modules/workstation/` — interactive base: Plasma, audio, gaming, nix gc
- `modules/homelab-client/` — the *using* side: tailnet, ntfy alerts, mounts
- `modules/notify.nix` — ntfy failure alerts, shared by server and clients
- `site.nix` — facts both sides need (domain, LAN IP, topic, timezone)
- `keys.nix` — the estate's public keys: the `admin` key and one host key each.
  A plain attrset at the root because the agenix CLI reads it outside the flake
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

Builds from the `nixpkgs-workstation` input, which it shares with the laptop: a
server-side pin exists for server reasons and must not gate a workstation. The
split is server-vs-workstation, not desktop-vs-laptop, so one command moves both
workstations and they never drift apart.

```sh
nix flake update nixpkgs-workstation   # both workstations
nix flake update nixpkgs               # server only
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

**4. The Samba login.** Set the password on the server with
`sudo smbpasswd -a wheezertbts`, then encrypt it for this host. The desktop's
host key is in `keys.nix`, so it decrypts the secret itself at activation:

```sh
cd hosts/frame-automata/secrets
agenix -e samba-client.age
```

with exactly these two lines — an editor rather than a heredoc, which
would put the password into your shell history:

```
username=wheezertbts
password=<the smbpasswd password>
```

Commit the resulting `.age` file, then rebuild. Shares mount on demand under
`/mnt/homelab/`; a secret that is missing or cannot be decrypted shows up as a
mount error on first access, not at build time.

If this host is ever reinstalled its host key changes, so the secret becomes
undecryptable: enroll the new `/etc/ssh/ssh_host_ed25519_key.pub` in `keys.nix`
and rekey with `agenix -r` from that directory. The `admin` key is what makes
that recoverable.

## Laptop (`frame-automobile`)

Acer Aspire A14-52MT — Core Ultra 5 226V "Lunar Lake", BE200 Wi-Fi 7. Same
module set as the desktop (`modules/workstation` + `modules/homelab-client`)
and the same `nixpkgs-workstation` input, so both workstations move together.
Two pieces are its own:

- `hosts/frame-automobile/power.nix` — battery and idle-power tuning, every
  value measured on this chassis: power-profiles-daemon kept over TLP so
  Plasma's profile switcher keeps working, an ASPM policy that matches what
  firmware shipped, runtime PM for the devices that came with it off, and Wi-Fi
  and HDA power saving. It also gates `nixos-upgrade`, `nix-gc` and
  `nix-optimise` on AC, so unattended maintenance never spends battery.
- `modules/common/intel-gpu.nix` — the Intel sibling of `amdgpu.nix`; adds the
  iHD VA-API driver so video decode happens on the GPU rather than the CPU.

It auto-upgrades weekly from `github:FrameAutomata/nix-config#frame-automobile`,
which resolves against the **default branch** — the config has to be merged for
the weekly upgrade to find it.

### No secrets on this host, deliberately

It holds no `secrets/` dir and no key in `keys.nix`, so it mounts no Samba
shares. The disk is unencrypted: a host key on it would be a standing
decryption capability for anyone who picks the laptop up, and `keys.nix` is the
one place where widening access is the mistake that is hard to walk back.

To change that, encrypt the disk first, then enroll
`/etc/ssh/ssh_host_ed25519_key.pub` in `keys.nix`, add
`hosts/frame-automobile/secrets/` with its own `secrets.nix`, and set
`homelabClient.mounts` the way `hosts/frame-automata/default.nix` does.

### It came off channels

This host ran a channel-based `/etc/nixos` config until 2026-08-23. Two
consequences worth remembering:

- `nix-channel --update` no longer affects the system. Upgrades come from the
  committed `flake.lock`, and a release hop is a change to the input URL.
- A bare `sudo nixos-rebuild switch` would rebuild the **old** channel config
  from `/etc/nixos/configuration.nix`. Always pass `--flake`.

### First boot — none of this is declarative

**1. A password.** The account sets none of
`hashedPassword`/`hashedPasswordFile`/`initialPassword` (a public repo is no
place for the first two), so a fresh install leaves it locked and SDDM rejects
every password. From a root TTY:

```sh
passwd frame-automobile
```

**2. Join the tailnet.** There is deliberately no `authKeyFile` — pre-auth keys
expire in 24h. Mint one on the server (`headscale preauthkeys create`), then:

```sh
sudo tailscale up --login-server https://wheezertbts.duckdns.org --auth-key <key> --accept-routes
```

**3. A new hardware scan.** `hosts/frame-automobile/hardware-configuration.nix`
is a committed scan of this machine. Regenerate it on a reinstall, and note that
a scan taken with no USB storage attached drops `usb_storage`/`sd_mod` — which
is why `default.nix` adds them back.
