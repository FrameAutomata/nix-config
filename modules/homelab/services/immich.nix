# Immich — self-hosted photo & video backup for the household. The native
# NixOS module stands up everything Immich needs on its own: a PostgreSQL with
# the vectorchord/pgvector extensions (smart search + face embeddings) and a
# unix-socket Redis. We only pick where the library lives, tune the ML memory
# behaviour for a shared 16 GB box, hang a LAN/tailnet vhost off it, and back
# up the one part that can't be re-derived — the database.
{ config, lib, ... }:
let
  cfg = config.homelab.services.immich;
  homelab = config.homelab;
  # Immich's default listen port. Ingress is the vhost only, so this never
  # needs a lanPorts entry — it stays bound to localhost.
  port = 2283;
  library = "${homelab.mounts.media}/Photos";
in
{
  options.homelab.services.immich.enable = lib.mkEnableOption "Immich photo & video backup";

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      # The library outgrows an SSD fast (roommate phone backups) and belongs
      # on the RAID1 pool, NOT the default /var/lib/immich. This must be a
      # REAL btrfs subvolume, created and chowned immich:immich by hand before
      # the first switch (see the manual step surfaced to Thomas) — the same
      # rule as Backups/ and the planned Recordings/, for the same reason: a
      # plain dir under the pool root is caught by btrbk's hourly snapshot
      # ladder, so every deleted photo and every regenerated thumbnail stays
      # pinned for up to 4 weeks. A nested subvolume is excluded from the
      # parent's snapshot, which is exactly what a large, churning media dir
      # wants. tmpfiles 'v' can't create it on this ext4-root box (degrades to
      # 'd'), and upstream's own tmpfiles only *adjusts* perms if it exists.
      mediaLocation = library;
      # localhost only — the vhost is the sole, access-controlled ingress
      host = "127.0.0.1";
      inherit port;
      openFirewall = false;
      # Leave app config (external domain, storage template, etc.) to the
      # first-run admin panel; pinning settings here would fight the web UI
      # and there's nothing we need declaratively yet.
      settings = null;

      machine-learning = {
        enable = true;
        environment = {
          # Unload the CLIP + face-detection models from RAM after 10 min
          # idle. On a 16 GB box shared with the whole stack we don't want
          # ~2-3 GB of resident models sitting between the occasional upload;
          # ML here is batch, not latency-sensitive, so paying the reload
          # cost on the next job is the right trade. (This is the plan's
          # "configure ML model idle-unloading".)
          MACHINE_LEARNING_MODEL_TTL = "600";
        };
      };
      # ML stays on CPU: accelerationDevices left at its default [] on
      # purpose. The lone GTX 1650 is already Jellyfin's transcode GPU
      # (nvidia.nix); handing it to Immich too would have the two contend
      # during a transcode/Live-TV session. Revisit only if batch ML times
      # get painful — the homelab library is small enough that CPU is fine.
    };

    # Nightly pg_dump of the Immich DB into /var/backup/postgresql. THIS, not
    # the live datadir, is what restic picks up: a torn copy of a running
    # Postgres datadir is worthless, whereas the dump is atomic (written
    # .in-progress then renamed) and consistent. Runs at 02:15, comfortably
    # before the 04:15 restic window; postgres stays up (the dump is the
    # artifact — no quiesce needed, and stopping it would drag Immich down).
    services.postgresqlBackup = {
      enable = true;
      databases = [ config.services.immich.database.name ];
      startAt = "*-*-* 02:15:00";
    };

    homelab.nginx.internal.photos = {
      proxyPass = "http://127.0.0.1:${toString port}";
      # Immich pushes upload/job progress over socket.io
      websockets = true;
      # Immich uploads a whole asset in one request — a 4K video is hundreds
      # of MB and the global services.nginx.clientMaxBodySize (10m on this
      # box) would 413 it. 0 = no limit, matching Immich's own documented
      # reverse-proxy example.
      clientMaxBodySize = "0";
      dashboard = {
        name = "Photos";
        description = "Photo & video backup";
        icon = "immich.svg";
        category = "Media";
      };
    };

    # Back up the DB dump only. The photo library (mediaLocation) is
    # deliberately kept out of BOTH restic repos: it already has RAID1
    # redundancy on the pool, a copy into the local repo would just
    # re-duplicate it on the same two disks, and shipping tens/hundreds of GB
    # of it to B2 would cost real money for data whose originals still live on
    # everyone's phones. What is irreplaceable is the DB — albums, faces,
    # shared links, users — and that is the dump above. If we ever decide the
    # library warrants offsite copies, add `library` here (and expect the B2
    # bill to move).
    homelab.services.backup.statePaths = [ config.services.postgresqlBackup.location ];

    # A silently failed dump would mean the DB quietly drops out of the
    # backup, so treat it like the other data-protection units and push on
    # failure.
    homelab.services.ntfy.notifyOnFailure = [ "postgresqlBackup-immich" ];

    # Keep the Immich library out of the [media] samba listing — it's private
    # (0700 immich:immich) and has no business in the communal share, same
    # treatment as Backups/.snapshots.
    homelab.services.samba.shares.media.vetoFiles = [ "Photos" ];
  };
}
