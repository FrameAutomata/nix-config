# nix-config — wheezertbts homelab + frame-automata desktop + frame-automobile laptop + wonudesktop
NixOS 26.05 flake. Four hosts: `wheezertbts` (live server; roommates depend on
it), `frame-automata` (Thomas's desktop, admin workstation),
`frame-automobile` (Thomas's laptop, no secrets on it) and `wonudesktop`
(girlfriend's desktop — 5800X3D/RTX 2070 Super, gaming + productivity; the one
host NOT administered by the person using it, NOT yet installed).

## Hard rules
- Never disable openssh / remove authorized keys / close port 22.
- Never break Headscale (apex vhost wheezertbts.duckdns.org → :8080, ports 80/443, DuckDNS timer).
- Secrets via agenix only; *File/environmentFile options, never inline.
- Build → test → switch; verify a fresh ssh session after network/firewall changes.
- Don't restructure /mnt/media data without explicit approval.

## Commands
- Rebuild: sudo nixos-rebuild switch --flake .#wheezertbts
  (or .#frame-automata, .#frame-automobile, .#wonudesktop)
- Safe try: sudo nixos-rebuild test --flake .#wheezertbts
- Rollback: sudo nixos-rebuild switch --rollback
- Secret edit (run from the secrets dir — the CLI resolves rules relative to cwd):
  cd hosts/wheezertbts/secrets      # server secrets
  cd hosts/frame-automata/secrets   # desktop secrets (samba-client.age)
  on the server (FILE must come right after -e, and sudo may drop $EDITOR):
    sudo EDITOR=nano agenix -e <name>.age -i /etc/ssh/ssh_host_ed25519_key
  on the desktop (admin key at ~/.ssh/id_ed25519): agenix -e <name>.age
  Keep the DUCKDNS_TOKEN=... env format when editing duckdns-token.age.

## Map
- hosts/wheezertbts/ — server config + its secrets
- hosts/frame-automata/ — desktop; modules/workstation + modules/homelab-client;
  has its own secrets/ dir. keys.nix (repo root) holds admin + one key per host;
  each host's secrets name only admin + that host, so neither can read the
  other's — widening them is the mistake to avoid
- hosts/frame-automobile/ — laptop; same module set as the desktop plus
  modules/common/intel-gpu.nix and a host-local power.nix. NO secrets dir and no
  key in keys.nix, deliberately: its disk is unencrypted, so a host key there
  would be a decryption capability for anyone holding the laptop
- hosts/wonudesktop/ — girlfriend's desktop; modules/workstation (NOT its
  dev.nix) + modules/common/nvidia.nix + host-local gpu.nix (RTX 2070 Super:
  open kernel modules, VRAM-preserving suspend) + modules/homelab-client.
  hardware-configuration.nix is a `throw` PLACEHOLDER until the machine is
  installed, so this host does not eval and `nix flake check` is red — expected,
  not a bug. Users: `wonu` (theirs, wheel) + `admin` (Thomas's key from
  keys.nix, wheel) with :22 open on tailscale0 ONLY — the estate's only
  workstation that opens ssh, because remote support is the whole point.
  LTS kernel (out-of-tree NVIDIA module), autoUpgrade operation = "boot" (a
  live driver swap breaks GL until reboot), Flatpak+Discover so its user can
  install apps without a commit. NO secrets/keys.nix entry YET — pending, not
  principled (unlike the laptop): enrolling a host key is step 1 of samba
  mounts. Also pending: homelab.household.members handle if they want a share
- All three workstations share the nixpkgs-workstation input; the server has its own
  nixpkgs. Never `nix flake update` bare — it moves everything. Update by name.
- modules/homelab/ — options + service modules (homelab.services.<name>)
- Packages: modules/common = all four hosts; modules/workstation = all three
  workstations (the shared interactive app set — edit once, not thrice);
  modules/workstation/dev.nix = the two hosts Thomas administers from (editors,
  nixd, gh, claude-code, headroom, direnv, nixos-release-check) — keep this off
  wonudesktop; a host's own systemPackages is for that machine alone (laptop:
  keyd; power.nix: powertop/turbostat; wonudesktop: heroic/lutris/protonup-qt).
  Not in nixpkgs -> pkgs/<name>/ + an overlay line in the flake's `shared` module.
- site.nix + modules/notify.nix — shared by all four hosts; edit once, not four times
- Plan & rationale: claude-code-homelab-plan.md / service-plan.md (Claude project)

## Current phase note
Phase 7 complete: btrbk hourly snapshots of the pool root (subvolume ".",
ladder 24h/7d/4w) into /mnt/media/.snapshots; restic nightly (04:15,
deliberately non-Persistent — no catch-up stop window at boot) to the
local repo /mnt/media/Backups/restic. The backup manifest is a registry:
service modules register homelab.services.backup.{statePaths,
quiesceUnits,excludePaths} inside their own mkIf; audit with nix eval
.#...backup.statePaths. Quiesced services stop-copy-start via
prepare/cleanup (cleanup is postStop, runs even on failure); adguardhome,
headscale, qbittorrent, samba stay up (live-copied). DynamicUser state
paths must be the /var/lib/private/* REAL paths (restic stores symlinks
as symlinks): prowlarr, seerr, uptime-kuma, AdGuardHome. Restore verified
end-to-end (restic-local dump + diff). Pruning runs in separate weekly
prune-only restic jobs (local-prune Sun, b2-prune Mon — outside the stop
window, with --retry-lock). /mnt/media/Backups must be a REAL btrfs
subvolume or snapshots pin superseded repo packs — tmpfiles 'v' degrades
to 'd' on this ext4-root box, so it was created manually. Pool root is
tmpfiles-pinned 1775 root:media (sticky: members can't rename Backups/
.snapshots away); both are also samba-vetoed. B2 offsite: a restic COPY
of the local repo (05:15, Persistent) — no second stop window; backup.b2
sub-options ready, waiting on Thomas's bucket + key -> b2-env.age.
Scrutiny at disks. (port 8085; its influxdb2 is memory-capped
GOMEMLIMIT/MemoryHigh/MemoryMax in scrutiny.nix). ntfy at ntfy. with
homelab-notify@ OnFailure hooks: restic (backup+prunes), btrbk, duckdns,
scrub, influxdb2, and every ACME cert auto-derived in ntfy.nix from
security.acme.certs — BOTH unit families (acme-<cert> AND
acme-order-renew-<cert>, the timers trigger the latter). Verified:
failure push arrives on topic "homelab". Onboarding of ALL users
deliberately deferred to the end (Thomas's call).

Onboarding tooling: welcome. static vhost (services/welcome.nix — member
self-guide; sections render only for enabled services;
homelab.nginx.internal now takes `root` as an alternative to proxyPass)
+ `sudo homelab-onboard <handle>` (onboard.nix): smbpasswd enroll,
FileBrowser account created WITH its /Private/<handle> jail (scope-
before-credentials by construction), headscale user + 24h pre-auth key,
prints a credential sheet. Re-runnable: existing accounts are left
unchanged. Media-app accounts (Jellyfin/Navidrome/ABS) stay manual until
their first-run wizards produce admin API tokens.

Music requests: Aurral at music-requests. (pkgs/aurral + services/aurral.nix,
port 3005 — 3001 is uptime-kuma). Seerr will NOT do music: both upstream
Lidarr PRs (#1226, #1238) were closed unmerged. Aurral has no approval
queue by design — per-user permissions are capability grants, so a member
with "add albums" writes straight to Lidarr, matching the auto-approve
policy Seerr already runs for video. PENDING MANUAL: its first-run wizard
(/api/onboarding/complete) REFUSES to finish without a reachable Lidarr URL
+ API key, so have those before first login; member accounts are then made
in Settings > Users (own login, not Jellyfin SSO). Packaging notes worth
keeping: sharp's npm prebuilt segfaults on dlopen even fully patchelfed, so
it is built from source against nixpkgs vips (SHARP_FORCE_GLOBAL_LIBVIPS);
node must be nodejs_22 (engine-strict + engines 22.23.x); the musl prebuilds
npm delivers must be deleted or autoPatchelfHook fails the build. Aurral
never writes the music library — only Lidarr does — so it needs no media
group; the optional yt-dlp/slskd download features would change that.

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
upstream tmpfiles rule set is mkForce-replaced so it can't chown the
mount (the pool root is managed only by homelab default.nix: 1775
root:media). Pending manual (§8): smbpasswd -a per member, roommate web-UI
accounts, FileBrowser jails, Kuma monitors, AdGuard/qBittorrent UI
passwords, arr interconnect wizards. Next: Phase 7 (btrbk, restic→B2,
Scrutiny, ntfy).
