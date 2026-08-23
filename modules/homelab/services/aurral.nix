# Aurral — the music counterpart to Jellyseerr: members sign in, search for
# an artist or album, and add it to Lidarr themselves.
#
# Deliberately NOT an approval queue. Aurral has no pending-request state;
# per-user permissions ("add artists or albums", "change monitoring",
# "delete") are capability grants, so a permitted member's add reaches Lidarr
# directly. That is the same policy already running for video — Jellyseerr on
# this host auto-approves — so the gate would have been decorative. Ombi is
# the alternative if a real queue is ever wanted; its music path is the part
# of Ombi with years-stale open bugs, which is why it lost here.
#
# Not packaged upstream: pkgs/aurral (a translation of its Dockerfile).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.services.aurral;
  # Upstream defaults to 3001, which uptime-kuma already holds on this host.
  # A `let` rather than an option: nothing outside this file needs to know,
  # and one binding keeps the unit and the vhost from ever disagreeing.
  port = 3005;
  stateDir = "aurral";
in
{
  options.homelab.services.aurral.enable = lib.mkEnableOption "Aurral music request portal";

  config = lib.mkIf cfg.enable {
    systemd.services.aurral = {
      description = "Aurral music request portal";
      wantedBy = [ "multi-user.target" ];
      # it reaches MusicBrainz and the Lidarr metadata API on startup
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        PORT = toString port;
        # Load-bearing, not a restatement of a default: left unset,
        # backend/config/data-dir.js falls back to <package>/backend/data —
        # a store path — and the first write fails on a read-only filesystem.
        AURRAL_DATA_DIR = "/var/lib/${stateDir}";
      };

      serviceConfig = {
        ExecStart = lib.getExe pkgs.aurral;
        Restart = "on-failure";
        RestartSec = "10s";

        DynamicUser = true;
        StateDirectory = stateDir;
        # the SQLite DB holds bcrypt password hashes and the session signing
        # secret, so it stays owner-only rather than systemd's 0755 default
        StateDirectoryMode = "0700";

        # Standard service hardening. Two knobs are absent on purpose:
        # MemoryDenyWriteExecute (V8 JITs, so it needs W|X and the unit would
        # not start) and ProcSubset=pid (node and its yt-dlp/ffmpeg children
        # read /proc/cpuinfo and /proc/meminfo for pool sizing).
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectProc = "invisible";
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = [ "" ];
        AmbientCapabilities = [ "" ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        SystemCallArchitectures = "native";
      };
    };

    homelab.services.backup = {
      # DynamicUser: the real state dir (see backup.nix statePaths docs)
      statePaths = [ "/var/lib/private/${stateDir}" ];
      # better-sqlite3 in WAL mode — stop-copy-start beats a torn snapshot,
      # and nobody is requesting albums at 04:15
      quiesceUnits = [ "aurral" ];
      excludePaths = [
        # re-fetched from Cover Art Archive / the Lidarr metadata API on demand
        "/var/lib/private/${stateDir}/image-proxy"
        "/var/lib/private/${stateDir}/discover-artwork"
        # yt-dlp staging: transient by construction, and anything complete has
        # already been handed to Lidarr
        "/var/lib/private/${stateDir}/downloads"
      ];
    };

    homelab.nginx.internal.music-requests = {
      proxyPass = "http://127.0.0.1:${toString port}";
      # the activity/queue views stream over a ws:// connection
      websockets = true;
      dashboard = {
        name = "Aurral";
        description = "Request music";
        icon = "aurral.svg";
        category = "Media";
      };
    };
  };
}
