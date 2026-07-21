# Safety net: hourly btrbk snapshots of the media pool (on-box only, they
# never leave the machine) + nightly restic backups of service state to
# (a) a local repo on the mirrored spinners — app state lives on the SSD,
# so this survives SSD death — and (b) a B2 offsite repo once credentials
# exist (homelab.services.backup.b2).
{ config, lib, ... }:
let
  cfg = config.homelab.services.backup;
  homelab = config.homelab;
  # Stopped for the brief 04:xx window so sqlite/bolt copies are consistent.
  # adguardhome (the LAN's DNS) and headscale (tailnet control) deliberately
  # stay up: live-copied, torn-copy risk accepted — their state is nix-managed
  # yaml plus small, loss-tolerable databases.
  quiescedUnits = [
    "vaultwarden"
    "jellyfin"
    "audiobookshelf"
    "navidrome"
    "filebrowser"
    "uptime-kuma"
    "sonarr"
    "radarr"
    "prowlarr"
    "seerr"
  ];
  statePaths = [
    "/var/lib/vaultwarden"
    "/var/lib/jellyfin"
    "/var/lib/audiobookshelf"
    "/var/lib/navidrome"
    "/var/lib/filebrowser"
    "/var/lib/sonarr"
    "/var/lib/radarr"
    # DynamicUser services keep state under private/ — /var/lib/<name> is a
    # symlink, and restic stores symlinks as symlinks (checked per service:
    # readlink /var/lib/<name>)
    "/var/lib/private/prowlarr"
    "/var/lib/private/seerr"
    "/var/lib/private/uptime-kuma"
    "/var/lib/private/AdGuardHome"
    "/var/lib/headscale"
    "/var/lib/qBittorrent"
    "/var/lib/samba" # smbpasswd database
    "/var/lib/tailscale" # this node's tailnet identity
  ];
  common = {
    passwordFile = cfg.passwordFile;
    paths = statePaths;
    exclude = [
      "/var/lib/jellyfin/transcodes"
      "/var/lib/jellyfin/cache"
      "/var/lib/navidrome/cache"
    ];
    initialize = true;
    backupPrepareCommand = "systemctl stop ${toString quiescedUnits}";
    # runs from postStop — executes even when the backup fails, so a bad
    # night never leaves services down
    backupCleanupCommand = "systemctl start ${toString quiescedUnits}";
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };
in
{
  options.homelab.services.backup = {
    enable = lib.mkEnableOption "btrbk snapshots + restic state backups";
    passwordFile = lib.mkOption {
      type = lib.types.path;
      default =
        (config.age.secrets.restic-password or (throw ''
          homelab.services.backup: the host must declare
          age.secrets.restic-password (the repo encryption password,
          shared by the local and B2 repos)
        '')).path;
      defaultText = "config.age.secrets.restic-password.path";
      description = "restic repository password file";
    };
    localRepo = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.media}/Backups/restic";
      description = "Local restic repository on the mirrored pool";
    };
    b2 = {
      enable = lib.mkEnableOption "offsite restic repo on Backblaze B2";
      repository = lib.mkOption {
        type = lib.types.str;
        description = "B2 repo URL, e.g. s3:s3.us-west-004.backblazeb2.com/<bucket>";
      };
      environmentFile = lib.mkOption {
        type = lib.types.path;
        default =
          (config.age.secrets.b2-env or (throw ''
            homelab.services.backup.b2: the host must declare
            age.secrets.b2-env (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY
            for the B2 application key)
          '')).path;
        defaultText = "config.age.secrets.b2-env.path";
        description = "EnvironmentFile with the B2 S3 credentials";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # hourly snapshot ladder of the whole pool
    services.btrbk.instances.media = {
      onCalendar = "hourly";
      settings = {
        timestamp_format = "long";
        snapshot_preserve_min = "6h";
        snapshot_preserve = "24h 7d 4w";
        volume.${homelab.mounts.media} = {
          snapshot_dir = ".snapshots";
          # the pool has no subvolume structure; "." is the fs root
          # subvolume (id=5), which btrbk supports on any modern fs
          subvolume.".".snapshot_name = "media";
        };
      };
    };

    systemd.tmpfiles.rules = [
      # btrbk requires the snapshot dir to exist
      "d ${homelab.mounts.media}/.snapshots 0700 root root -"
      # 'v' = btrfs subvolume: keeps the restic repo out of the hourly root
      # snapshots, so the ladder doesn't pin superseded repo blocks
      "v ${homelab.mounts.media}/Backups 0700 root root -"
      "d ${cfg.localRepo} 0700 root root -"
    ];

    services.restic.backups = {
      local = common // {
        repository = cfg.localRepo;
        timerConfig = {
          OnCalendar = "04:15";
          Persistent = true;
        };
      };
    }
    // lib.optionalAttrs cfg.b2.enable {
      b2 = common // {
        repository = cfg.b2.repository;
        environmentFile = cfg.b2.environmentFile;
        timerConfig = {
          OnCalendar = "04:45";
          Persistent = true;
        };
      };
    };

    homelab.services.ntfy.notifyOnFailure = [
      "restic-backups-local"
      "btrbk-media"
    ]
    ++ lib.optional cfg.b2.enable "restic-backups-b2";
  };
}
