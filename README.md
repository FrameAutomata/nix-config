# nix-config

NixOS flake for the `wheezertbts` household homelab server, the `frame-automata`
desktop that administers it, the `frame-automobile` laptop, and `wonudesktop` —
the second desktop, someone else's daily driver.

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
sudo nixos-rebuild switch --flake .#wonudesktop      # the second desktop
sudo nixos-rebuild switch --rollback             # undo
```

## Structure

- `hosts/wheezertbts/` — server config + its agenix secrets; `tv.nix` is the
  living-room TV seat (cage kiosk + Jellyfin Desktop on the GTX 1650's HDMI)
- `hosts/frame-automata/` — desktop config + its own agenix secrets; also holds
  the `admin` key that edits *both* sets, so it is the recovery path if either
  host key rotates
- `hosts/frame-automobile/` — laptop config; no secrets and no key in `keys.nix`
- `hosts/wonudesktop/` — second desktop (5800X3D / RTX 2070 Super), someone
  else's daily driver; NVIDIA gaming layer in its own `gpu.nix`, no secrets yet
- `modules/common/` — host-agnostic base (locale, nix settings, ssh, gpu;
  `amdgpu.nix`, `intel-gpu.nix`, `nvidia.nix` and `audio.nix` are opt-in per
  host — `audio.nix` is the PipeWire stack the workstations and the TV seat share)
- `modules/workstation/` — interactive base: Plasma, gaming, nix gc (audio via
  `modules/common/audio.nix`).
  Two opt-in `dev-*.nix` layers sit on top, imported only by the hosts this
  repo is deployed from: `dev-tools.nix` (editors, `nixd`, `gh`, `claude-code`,
  direnv, the release check) and `dev-databases.nix` (PostgreSQL + ClickHouse
  for Traceway). Anything true of *every* interactive machine stays in
  `default.nix`
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

## Living-room TV (`wheezertbts` → HDMI)

The server's GTX 1650 has an HDMI port and the living-room TV is on the other
end of it. `hosts/wheezertbts/tv.nix` makes the box boot straight into
Jellyfin: `cage`, a Wayland compositor that shows exactly one window, takes
tty1 and runs Jellyfin Desktop in its 10-foot layout as a dedicated locked
user `tv`. No desktop, no login screen, nothing else on the panel. It is
host-local because there is one TV: a `modules/homelab/services/` module would
parameterise the user, program, sink ranking and VT for no second consumer, and
hand anyone enabling it a unit that seizes tty1. It is deliberately *not*
`modules/workstation` either, which is a desktop for a person at a desk. The one
thing both need, PipeWire, moved to
`modules/common/audio.nix`.

Jellyfin Desktop loads the web client **from the server** (its bundled page is
only a server-address prompt), and that is what makes the Netflix-style "Who's
watching?" gate possible: the Bonfire (JellyProfiles) plugin injects its script
into the web client the server serves, so it appears on the TV, in the phone
app and in a browser alike — everywhere except the native TV apps. Playback is
mpv with NVDEC, and the session is an ordinary Jellyfin client, so a phone's
**Play on** target works as a remote with no hardware at all.

What a deploy does and does not do. `cage-tty1` is `restartIfChanged = false`,
so a switch never kills a viewing session: a new Jellyfin Desktop arrives at
the next `sudo systemctl restart cage-tty1` (when nobody is watching) or
reboot. Deploy **over ssh, never from tty1** — activation starts `cage-tty1`,
which takes tty1 from `getty`; the console is on tty2 (Ctrl+Alt+F2, cage runs
with `-s` so VT switching works). `graphical.target` becomes the default
target, an admin ssh login now gets PipeWire's user sockets (the daemon
itself stays socket-activated and does not spawn), and logind
ignores the power button: roommates are within reach of the box now, the TV's
remote is the off switch, and ssh administers the server. Immediate escape
without a rollback:

```sh
sudo systemctl stop cage-tty1 && sudo systemctl start getty@tty1

# and if it gave up after ten failed starts in an hour (ntfy will have said so):
sudo systemctl reset-failed cage-tty1 && sudo systemctl start cage-tty1
```

After a deploy: `systemctl status cage-tty1` (if inactive, `sudo systemctl
start cage-tty1` — `graphical.target` only becomes the default at boot);
`journalctl -u cage-tty1 -b`, where "could not load the Qt platform plugin"
means the Wayland QPA did not come up (switch the session to `--platform
xcb`) and "no input devices" means the env var did not reach cage;
`loginctl list-sessions` shows `tv` on seat0. Audio:

```sh
sudo -u tv env XDG_RUNTIME_DIR=/run/user/$(id -u tv) wpctl status
```

should list the HDMI node as the default sink. It exists only while the TV is
on, and if the onboard HDA turns out to expose an HDMI sink of its own the
regex in `tv.nix` matches both — narrow it to the name `wpctl` shows. Knobs if
the compositor will not start on the proprietary driver, in order:
`WLR_NO_HARDWARE_CURSORS=1` in `services.cage.environment`, swapping
that block's `QT_QPA_PLATFORM` for `--platform xcb` on the wrapper's exec
line, `--disable-gpu`, and `hardware.nvidia.open = true`
(Turing is on upstream's recommended side; it needs a reboot).

### First run — none of this is declarative

**1. A Jellyfin account for the TV.** Dashboard → Users → add `livingroom`:
not an administrator, password set, "Allow remote connections" unticked (it
only ever connects from `127.0.0.1`), optionally hidden from login pages. If
the TV is an OLED, set a screensaver in its display settings — the box never
sends "no signal", so the TV will not switch itself off.

**2. On the TV.** Server `http://127.0.0.1:8096`, straight to Jellyfin. The
`jellyfin.` vhost resolves on this box too (`nginx.nix` pins every internal
name to the LAN IP), but that path goes through the proxy's TLS and ACL for
nothing. Log in as `livingroom`, remember. Client state lives in
`/home/tv/.local/share/jellyfin-desktop/`; it is not backed up, and re-entering
the URL is the whole recovery.

**3. Bonfire.** Dashboard → Plugins → Repositories → add
`https://ahouseofbards.github.io/Bonfire-JellyProfiles/manifest.json` →
Catalog → install → `sudo systemctl restart jellyfin`. Plugin and config land
in `/var/lib/jellyfin/plugins`, already inside `backup.statePaths`.

**4. Profiles.** Set `livingroom`'s switcher to the full-screen "Who's
Watching?" mode, one profile per roommate, PINs optional. Leave "bypass PIN on
own network" **off**: the TV always connects from `127.0.0.1`, so bypass would
make every PIN moot on the TV. Write the emergency disable code down somewhere
safe. Check on first run that the gate renders inside the `--tv` layout — both
Bonfire and Jellyfin Desktop inject JS; Bonfire lists Jellyfin Media Player as
supported.

**5. Music.** Dashboard → Libraries → Add → content type Music, folder
`/mnt/media/Music`. Lidarr writes that tree and Navidrome reads it, both in
group `media`, and the `jellyfin` user is already in `media`, so nothing in
the config changes. Turn the internet metadata fetchers **off** for this
library: Lidarr already tags files and drops folder art, and Jellyfin must only
ever read here. Give `livingroom` access; Bonfire's per-profile library access
decides which profiles see it. Jellyfin becomes a second catalog of the same
files — favourites, play counts and playlists do not sync with Navidrome,
which stays the music server for phones.

**6. Input, cheapest first.** Nothing, via **Play on** in the phone's Jellyfin
app; any USB / 2.4 GHz / Bluetooth keyboard or air-mouse (the TV layout is
arrow-key driven); an SDL2 gamepad; a Pulse-Eight USB-CEC adapter for the TV's
own remote (the 1650 has no CEC line; Jellyfin Desktop is built with libcec).
Whether the server has Bluetooth is unknown — if it does,
`hardware.bluetooth.enable = true` in `tv.nix` and pair over ssh.

### The trade-offs, stated once

- **Profiles under one shared account** keep TV watch history separate from a
  roommate's personal Jellyfin account (phones, the Jellyseerr login). The
  alternative — each roommate signing their own account in on the TV — gives
  one history but no gate.
- **No HDR from Jellyfin Desktop, under any compositor.** Its mpv output is
  composited through Qt Quick, so HDR titles play tone-mapped to SDR (upstream
  issue #523, open since 2023). True HDR on Linux is a standalone mpv
  (`vo=gpu-next` with `target-colorspace-hint`) under an HDR-capable
  compositor — sway with its Vulkan renderer, or KWin — glued to Jellyfin by
  `jellyfin-mpv-shim` as a **Play on** target, browsing from the phone. The
  shakiest link is wlroots' Vulkan renderer on the proprietary NVIDIA driver,
  and nothing found proves it on this card, so no sway config gets written on
  speculation. The spike that decides, ad hoc on the server: stop `cage-tty1`,
  start sway as `tv` with `WLR_RENDERER=vulkan`, `output * hdr on`,
  `render_bit_depth 10` and a mode the HDMI 2.0b link carries at 10-bit
  (`3840x2160@30Hz` or `1920x1080@60Hz`), then play an HDR10 sample with
  `mpv --vo=gpu-next --target-colorspace-hint=yes
  --target-colorspace-hint-mode=source --hwdec=nvdec`. Pass means the TV's own
  overlay says HDR/PQ and the picture is not washed out; only then does cage
  become sway with mpv-shim in the session. If sway refuses the renderer, the
  fallbacks are a Plasma session (KWin HDR is the most-reported working path
  on NVIDIA) or a streaming stick for HDR with the kiosk staying SDR. Kodi is
  out either way: HDR only on its GBM backend, no NVDEC, and its own community
  calls NVIDIA + GBM + HDR unsupported.

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
nix fmt   # generate-config output is NOT nixfmt-clean; checks.formatting gates it
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

### Swap and hibernation

The unencrypted disk shapes swap too, and there the tradeoff went the other
way. The machine has 16 GiB of RAM and shipped with none, and there is no free
partition space (`nvme0n1` is `/boot` plus one full-disk ext4 root, and ext4
cannot be shrunk while mounted), so `hosts/frame-automobile/default.nix` adds
a 16 GiB **swapfile** at `/var/lib/swapfile`. On ext4 that is not a
compromise: the kernel resolves the file's extents once at `swapon` and then
writes straight to the block device, so a partition would buy nothing but a
risky offline repartition.

`randomEncryption` was the first cut — a fresh key per boot, so nothing paged
out stayed readable on a disk that travels — but it is mutually exclusive with
hibernation, and hibernation won. This chassis offers only `s2idle`, no S3
(`cat /sys/power/mem_sleep`), so a closed lid drains overnight in a way
hibernate avoids. **The accepted cost is that swap, and the full RAM image
hibernation writes, sit in plaintext on an unencrypted disk.** Encrypting the
disk is the change that would get both; until then this is the weakest point on
this host.

Hibernation needs two things. `boot.resumeDevice` names the filesystem holding
the swapfile and is read from `fileSystems."/"`, so a fresh hardware scan
carries it. The second is `resume_offset`, the block offset of the file itself,
which cannot be known until the file exists. It lives in the
`swapfileResumeOffset` binding at the top of the host config; `null` there is
legal and simply drops the kernel param, which is the right state whenever the
file's location is unknown. Re-measure after any switch that recreates the
swapfile:

```
sudo filefrag -v /var/lib/swapfile |
  awk '$1=="0:" {print substr($4, 1, length($4) - 2); exit}'
```

ext4 blocks and kernel pages are both 4096 here, so that number goes in
verbatim. Re-measure if the file is ever recreated (changing `size` does that);
a stale offset corrupts nothing, but resume finds no valid image and boots
fresh, silently losing the session.

Closing the lid is wired to suspend-then-hibernate in
`hosts/frame-automobile/power.nix`: suspend first, then hibernate after
`HibernateDelaySec=30min`, so a short close resumes from RAM and a long one
settles at roughly zero draw. On external power it stays plain suspend.

**One half of this is manual, and without it the lid does nothing new.**
`services.logind.settings.Login.HandleLidSwitch` only reaches the lid when
nothing holds logind's `handle-lid-switch` inhibitor — the SDDM login screen, a
TTY. Inside a Plasma session PowerDevil takes that inhibitor as a *block* and
owns the lid itself (`systemd-inhibit --list` shows it, as `KDE handles power
events`). PowerDevil 6.6 does support the mode — it calls logind's
`SuspendThenHibernate`, which reports `yes` on this host — but the setting is
per-user Plasma state and this repo runs no home-manager, so it cannot be
declared here:

> System Settings → Power Management → **Sleep mode** → **"Standby, then
> hibernate"**, leaving the lid-close action itself on "Sleep".

Plasma 6.6 restructured this: the per-trigger dropdowns no longer each list
suspend/hibernate/hybrid. There is now one **Sleep mode** selector defining what
"Sleep" means, and the triggers just say "Sleep". The entry is called *Standby,
then hibernate* — not "sleep" — which is easy to look straight past. It is
`SleepMode` in `~/.config/powerdevilrc` once set, so the value can be read back
and promoted to a system default in `/etc/xdg/` later if that is worth doing.

`HibernateDelaySec` governs the gap whoever invokes the sleep, so the
declarative half is still doing work once that is set.

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

## Second desktop (`wonudesktop`)

The old AM4 box — Ryzen 7 5800X3D, RTX 2070 Super — rebuilt as somebody else's
daily driver: gaming and productivity, no Windows license, and a user who has
used Windows and macOS but never a machine that did not come in one piece from
a manufacturer. That last fact is what shaped this config. It is the only host
in the estate that is not administered by the person sitting at it, so where a
choice trades a little of the admin's convenience for a machine that does not
surprise its user, it goes that way — and the reason is in the file.

Same `nixpkgs-workstation` input as the other two workstations, so all three
move together and a bad revision is never true on one and false on another.

What differs from `frame-automata`, which is otherwise the same class of
machine:

- **`modules/workstation`, but neither `dev-*.nix` layer.** The Plasma / audio
  / Steam / browser / LibreOffice base is shared by every interactive machine;
  the editors, terminals, `nixd`, `gh`, `claude-code`, `headroom`, direnv and
  the NixOS-release check live in `dev-tools.nix`, and the Traceway databases
  in `dev-databases.nix`. Both are imported per host, by the two machines this
  repo is deployed from. The split is admin-vs-not, not desktop-vs-laptop, so
  there is still exactly one place to edit anything true of all three
  workstations.
- **The LTS kernel** (`pkgs.linuxPackages`, 6.18) rather than
  `linuxPackages_latest` (7.2). The other two hosts have in-tree GPU drivers,
  so tracking mainline is free there. Here the NVIDIA module is an out-of-tree
  build that has to catch up to each kernel release, and the window where it
  has not is a machine that boots to a black screen.
- **Open NVIDIA kernel modules** (`hardware.nvidia.open = true`, in
  `hosts/wonudesktop/gpu.nix`). Turing is exactly where upstream's own advice
  flips — the nvidia module says to use the open modules on Turing and later,
  the closed ones below it — and open is also what enables the driver's kernel
  suspend-notifier path on 595+. The server keeps the closed module;
  `modules/common/nvidia.nix` now says `open = lib.mkDefault false` so that is
  a per-card decision rather than a house rule. Paired with
  `powerManagement.enable`, which preserves VRAM across suspend: without it
  NVIDIA documents the contents as undefined after a wake, and "the desktop
  came back corrupted" is the failure this machine's user is least equipped to
  deal with.
- **The weekly upgrade applies at the next boot**, `operation = "boot"` rather
  than `"switch"`. A switch that lands a new NVIDIA release swaps the userspace
  libraries under a running session while the loaded kernel module stays where
  it was, and nothing can open a GL context until a reboot. On an admin's
  machine that is a recognisable annoyance; here it is a computer that broke
  itself mid-afternoon with nobody to explain why.
- **Flatpak and Discover.** Enabling `services.flatpak` is what makes Plasma
  ship Discover at all (its PackageKit backend has no Nix support). A
  `flathub-remote` oneshot registers Flathub, since remotes have no NixOS
  option; it is deliberately *not* ordered after `network-online.target`,
  which is on the path to the login screen, and instead fails fast and retries.
  The trade is explicit: apps installed this way are not declarative and not in
  this repo. On a machine whose user cannot be expected to open a pull request
  to get Spotify, the alternative is not a tidier config — it is a person who
  cannot install anything.
- **SSH reachable on `tailscale0` only, plus an `admin` account.** This is the
  first workstation in the estate that opens :22, because "walk over and look
  at it" is not a support path for someone else's computer. The tailscale
  module does not put its own interface in `trustedInterfaces`, so nothing is
  implied by the tailnet being up; the port never appears on the LAN. The
  `admin` account carries the `admin` key from `keys.nix` and exists so that
  the user can change their own password without cutting off support.
- **Windows-refugee ergonomics**: metric-compatible fonts (Liberation, Carlito,
  Caladea) so a `.docx` in Arial or Calibri does not reflow, CUPS + Avahi for
  driverless network printers, zram instead of an OOM kill, and
  `/etc/xdg/kdeglobals` setting `SingleClick=false` — a system *default*, not a
  lock, so the moment they change it in System Settings their own config wins.

### First boot — none of this is declarative

**1. Hardware scan.** `hosts/wonudesktop/hardware-configuration.nix` is a
`throw` placeholder, so the host does not evaluate at all until it is replaced
(and `nix flake check` is red for the repo meanwhile — that is this file
talking, not a broken config; the other three hosts are separate evals and are
unaffected). Install in **UEFI mode**: `modules/common` uses systemd-boot.

```sh
nixos-generate-config --root /mnt          # from the installer
# copy /mnt/etc/nixos/hardware-configuration.nix to hosts/wonudesktop/
nix fmt   # generate-config output is NOT nixfmt-clean; checks.formatting gates it
nixos-install --flake .#wonudesktop
```

**Commit and push the scan.** `system.autoUpgrade` builds from
`github:FrameAutomata/nix-config`, so an uncommitted scan means local rebuilds
work while every weekly upgrade dies on the placeholder.

**2. Two passwords.** No account sets `hashedPassword`/`initialPassword` — a
public repo is no place for either — so a fresh install leaves both locked and
SDDM rejects every password. From a root TTY:

```sh
passwd wonu     # theirs; hand it over and let them change it
passwd admin    # Thomas's, for sudo after an SSH login
```

The `admin` account is key-only over SSH (`PasswordAuthentication = false`),
but it still needs a local password, because sudo asks for one.

**3. Check the username before installing, not after.** The account is `wonu`
because the host is `wonudesktop`; every other host in this repo names its user
after the machine, which works only because those accounts are all Thomas's. A
username owns the home directory, the Steam library and the Plasma config, so
changing it later is real work — and if this person is ever given a homelab
share, life is simplest when this handle matches their
`homelab.household.members` handle.

**4. Join the tailnet.** No `authKeyFile`; pre-auth keys expire in 24h. Mint one
on the server (`headscale preauthkeys create`), then:

```sh
sudo tailscale up --login-server https://wheezertbts.duckdns.org --auth-key <key> --accept-routes
```

Until this is done, SSH has no route in and `nixos-upgrade` failures have
nowhere to publish.

**5. Plasma settings that cannot be declared.** This repo runs no home-manager,
so per-user Plasma state is manual — same limitation as the laptop's lid
behaviour. Worth doing with them on day one:

> - The SDDM session picker offers **Plasma (Wayland)** and **Plasma (X11)**.
>   Wayland is the default and is the right one on this driver; X11 is the
>   fallback if something specific misbehaves.
> - Discover → Settings → check Flathub is listed (the `flathub-remote` unit
>   registers it; `systemctl status flathub-remote` if it is not).
> - Steam → Settings → Compatibility → enable Proton for all titles.

### Deliberately not wired up yet

- **No Samba mounts and no secrets.** This host has no key in `keys.nix`, so it
  cannot decrypt a `samba-client` secret of its own. Unlike the laptop, that is
  not a standing decision — it is just a machine that does not exist yet. To
  change it: enroll `/etc/ssh/ssh_host_ed25519_key.pub` in `keys.nix`, add
  `hosts/wonudesktop/secrets/` with its own `secrets.nix` naming only `admin`
  and this host, add `agenix.nixosModules.default` to its module list in
  `flake.nix`, and set `homelabClient.mounts` the way
  `hosts/frame-automata/default.nix` does.
- **No household membership.** A private share on the server means a handle in
  `homelab.household.members` (server-side, their agreed nickname, `smbpasswd
  -a` and the onboarding sheet from `sudo homelab-onboard <handle>`). That is
  their decision to make, not something to do on their behalf.
- **Nothing on this machine is backed up.** The homelab's restic and btrbk jobs
  cover server state only. Documents saved to this desktop's home directory
  exist in exactly one place until the two items above are done and they start
  saving to their share.

### What Linux will not do, and it is better to say so first

Steam plus Proton covers the large majority of a modern library, and this
machine has the hardware for it. The exceptions are worth naming before someone
is disappointed by them:

- **Games with kernel-level anti-cheat** — Valorant, Fortnite, Destiny 2, and
  others — do not run and will not be made to. Check a library against
  [ProtonDB](https://www.protondb.com) and
  [areweanticheatyet.com](https://areweanticheatyet.com) *before* promising
  anything.
- **Adobe's desktop apps** (Photoshop, Lightroom, Premiere) have no supported
  path here.
- **Desktop Microsoft Office** does not install. Office on the web works in a
  browser, LibreOffice is installed, and OnlyOffice
  (`pkgs.onlyoffice-desktopeditors`, or the Flathub build) is the closest match
  for `.docx` fidelity if LibreOffice's rendering ever grates.
