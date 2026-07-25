# Books, in two instances. Upstream Readarr is RETIRED (metadata service
# dead, project archived): the binary is fine and still speaks Prowlarr +
# qBittorrent, but each instance must be pointed at a community metadata
# mirror by hand — http://<vhost>/settings/development (a page the UI never
# links) -> Metadata Provider Source -> https://api.bookinfo.pro. That is
# UI state in each config.xml, which the backup registry below captures.
# Successor to watch: Chaptarr, a fork that does both formats in one
# instance; it's alpha and container-only, so not yet worth the podman
# dependency on this box.
{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = homelab.services.readarr;
  # Stock Readarr tracks ONE format per instance — it can't keep the ebook
  # and audiobook editions of a book in separate root folders — so ebooks
  # and audiobooks need separate instances. services.readarr (nixpkgs) is
  # the ebook side; the audiobook side is the same package under a second
  # unit with its own data dir and port.
  ebook = config.services.readarr;
  audioDataDir = "/var/lib/readarr-audiobooks";
in
{
  options.homelab.services.readarr = {
    enable = lib.mkEnableOption "Readarr ebook + audiobook managers";
    audiobookPort = lib.mkOption {
      type = lib.types.port;
      default = 8788;
      description = ''
        Port for the audiobook instance. The ebook instance keeps the
        upstream default (services.readarr.settings.server.port = 8787).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.readarr = {
      enable = true;
      group = homelab.group;
    };

    systemd.services.readarr-audiobooks = {
      description = "Readarr (audiobooks)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      # inherited from the ebook unit so the two can't drift on the update
      # mechanism / analytics settings nixpkgs pins; only the port differs
      environment = config.systemd.services.readarr.environment // {
        READARR__SERVER__PORT = toString cfg.audiobookPort;
      };
      serviceConfig = {
        Type = "simple";
        User = ebook.user;
        Group = ebook.group;
        EnvironmentFile = ebook.environmentFiles;
        ExecStart = "${ebook.package}/bin/Readarr -nobrowser -data='${audioDataDir}'";
        Restart = "on-failure";
      };
    };

    systemd.tmpfiles.rules = [
      # second instance's state (upstream's own rule covers the first)
      "d ${audioDataDir} 0700 ${ebook.user} ${ebook.group} -"
      # root folders, one per format. setgid: imports land group-writable to
      # ${homelab.group} so Audiobookshelf and the household can read them
      # without a chown pass later.
      "d ${homelab.mounts.media}/Books 2775 root ${homelab.group} -"
      "d ${homelab.mounts.media}/Audiobooks 2775 root ${homelab.group} -"
    ];

    homelab.services.backup = {
      statePaths = [
        "/var/lib/readarr"
        audioDataDir
      ];
      quiesceUnits = [
        "readarr"
        "readarr-audiobooks"
      ];
    };

    homelab.nginx.internal = {
      books = {
        proxyPass = "http://127.0.0.1:${toString ebook.settings.server.port}";
        dashboard = {
          name = "Readarr (eBooks)";
          description = "Ebook automation";
          icon = "readarr.svg";
          category = "Downloads";
        };
      };
      audiobooks = {
        proxyPass = "http://127.0.0.1:${toString cfg.audiobookPort}";
        dashboard = {
          name = "Readarr (Audiobooks)";
          description = "Audiobook automation";
          icon = "readarr.svg";
          category = "Downloads";
        };
      };
    };
  };
}
