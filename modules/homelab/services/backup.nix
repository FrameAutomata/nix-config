# Safety net: hourly btrbk snapshots of the media pool (on-box only, they
# never leave the machine) + nightly restic backups of service state to
# (a) a local repo on the mirrored spinners — app state lives on the SSD,
# so this survives SSD death — and (b) a B2 offsite copy of that repo once
# credentials exist (homelab.services.backup.b2).
#
# What gets backed up is registered by the owning service modules
# (statePaths / quiesceUnits / excludePaths), so the manifest tracks
# service enablement. Audit it with:
#   nix eval .#nixosConfigurations.<host>.config.homelab.services.backup.statePaths
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.services.backup;
  homelab = config.homelab;
  mkSecretOption = import ../secret-option.nix { inherit lib config; };
  keepOpts = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
in
{
  options.homelab.services.backup = {
    enable = lib.mkEnableOption "btrbk snapshots + restic state backups";
    statePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        State directories to back up — registered by the owning service
        modules. DynamicUser services must register their real
        /var/lib/private/<name> path: /var/lib/<name> is a symlink there,
        and restic stores symlinks as symlinks.
      '';
    };
    quiesceUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Units stopped for the nightly backup window so sqlite/bolt copies
        are consistent — registered by the owning service modules. Services
        whose downtime hurts more than a torn copy register statePaths only
        and accept live copies.
      '';
    };
    excludePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Regenerable cache/transcode paths excluded from backup — registered by the owning service modules";
    };
    passwordFile = mkSecretOption {
      secret = "restic-password";
      optionPath = "homelab.services.backup";
      hint = "the repo encryption password, shared by the local and B2 repos";
      description = "restic repository password file";
    };
    localRepo = lib.mkOption {
      type = lib.types.str;
      default = "${homelab.mounts.media}/Backups/restic";
      description = "Local restic repository on the mirrored pool";
    };
    b2 = {
      enable = lib.mkEnableOption "offsite restic copy to Backblaze B2";
      repository = lib.mkOption {
        type = lib.types.str;
        description = "B2 repo URL, e.g. s3:s3.us-west-004.backblazeb2.com/<bucket>";
      };
      environmentFile = mkSecretOption {
        secret = "b2-env";
        optionPath = "homelab.services.backup.b2";
        hint = "AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY for the B2 application key";
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
      # the repo parent must be its own subvolume so the hourly snapshot
      # ladder doesn't pin superseded repo blocks. 'v' only creates a real
      # subvolume when / itself is btrfs (tmpfiles.d(5)); on other roots it
      # degrades to a plain dir — create it by hand once:
      #   btrfs subvolume create <dir>
      "v ${dirOf cfg.localRepo} 0700 root root -"
      "d ${cfg.localRepo} 0700 root root -"
    ];

    # keep the repo and snapshot dirs out of [media] share listings; the
    # pool root's sticky bit (homelab default.nix) stops members renaming
    # them away, which would silently detach the backup history
    homelab.services.samba.shares.media.vetoFiles = [
      "Backups"
      ".snapshots"
    ];

    services.restic.backups.local = {
      repository = cfg.localRepo;
      passwordFile = cfg.passwordFile;
      paths = cfg.statePaths;
      exclude = cfg.excludePaths;
      initialize = true;
      # deliberately NOT Persistent: a catch-up run after downtime spanning
      # 04:15 would fire the service-stop window right at boot — peak usage;
      # the next scheduled night is soon enough
      timerConfig.OnCalendar = "04:15";
    }
    // lib.optionalAttrs (cfg.quiesceUnits != [ ]) {
      backupPrepareCommand = "systemctl stop ${toString cfg.quiesceUnits}";
      # runs from postStop — executes even when the backup fails, so a bad
      # night never leaves services down
      backupCleanupCommand = "systemctl start ${toString cfg.quiesceUnits}";
    };

    # cold-starting ~10 services in the cleanup command can exceed the
    # default 90 s stop timeout (which covers postStop) — a SIGKILL there
    # marks the backup failed even though the services do come back
    systemd.services.restic-backups-local.serviceConfig.TimeoutStopSec = "15min";

    # prune weekly, in separate prune-only jobs (empty paths = no backup
    # command): keeps repack I/O out of the nightly service-stop window,
    # and upstream runs `restic unlock` first so a crashed run's stale
    # lock can't wedge pruning forever. --retry-lock rides out a copy or
    # backup that overruns into the prune slot.
    services.restic.backups.local-prune = {
      repository = cfg.localRepo;
      passwordFile = cfg.passwordFile;
      pruneOpts = keepOpts ++ [ "--retry-lock 1h" ];
      timerConfig = {
        OnCalendar = "Sun 06:30";
        Persistent = true;
      };
    };
    services.restic.backups.b2-prune = lib.mkIf cfg.b2.enable {
      repository = cfg.b2.repository;
      passwordFile = cfg.passwordFile;
      environmentFile = cfg.b2.environmentFile;
      pruneOpts = keepOpts ++ [ "--retry-lock 1h" ];
      timerConfig = {
        OnCalendar = "Mon 06:30";
        Persistent = true;
      };
    };

    # B2 receives a `restic copy` OF THE LOCAL REPO: no second stop window,
    # no second read of /var/lib, bit-identical snapshots, and cross-repo
    # dedup via --copy-chunker-params at init.
    systemd.services.restic-b2-copy = lib.mkIf cfg.b2.enable {
      description = "Copy restic snapshots to B2";
      # the Persistent timer can fire a catch-up right at boot, before the
      # network is up — and a transient S3 failure of `cat config` would
      # fall through to a doomed `init`
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.restic ];
      environment = {
        RESTIC_REPOSITORY = cfg.b2.repository;
        RESTIC_PASSWORD_FILE = cfg.passwordFile;
        RESTIC_FROM_REPOSITORY = cfg.localRepo;
        RESTIC_FROM_PASSWORD_FILE = cfg.passwordFile;
        RESTIC_CACHE_DIR = "/var/cache/restic-b2-copy";
      };
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.b2.environmentFile;
        CacheDirectory = "restic-b2-copy";
      };
      script = ''
        restic cat config >/dev/null 2>&1 || restic init --copy-chunker-params
        restic copy --cleanup-cache --retry-lock 1h
      '';
    };
    systemd.timers.restic-b2-copy = lib.mkIf cfg.b2.enable {
      wantedBy = [ "timers.target" ];
      # after the 04:15 local run; Persistent is safe here — no stop window
      timerConfig = {
        OnCalendar = "05:15";
        Persistent = true;
      };
    };

    homelab.services.ntfy.notifyOnFailure = [
      "restic-backups-local"
      "restic-backups-local-prune"
      "btrbk-media"
    ]
    ++ lib.optionals cfg.b2.enable [
      "restic-b2-copy"
      "restic-backups-b2-prune"
    ];
  };
}
