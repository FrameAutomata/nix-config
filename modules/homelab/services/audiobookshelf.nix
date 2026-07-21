{ config, lib, ... }:
let
  cfg = config.homelab.services.audiobookshelf;
in
{
  options.homelab.services.audiobookshelf.enable = lib.mkEnableOption "Audiobookshelf";

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      # direct port stays open for LAN app traffic
      openFirewall = true;
      host = "0.0.0.0"; # defaults to localhost-only, which blocks every other device
    };
    homelab.nginx.internal.abs = {
      proxyPass = "http://127.0.0.1:${toString config.services.audiobookshelf.port}";
      websockets = true; # the abs web UI is socket.io-based
      dashboard = {
        name = "Audiobookshelf";
        description = "Audiobooks & podcasts";
        icon = "audiobookshelf.svg";
        category = "Media";
      };
    };
    users.groups.${config.homelab.group}.members = [ "audiobookshelf" ];

    homelab.services.backup = {
      statePaths = [ "/var/lib/audiobookshelf" ];
      quiesceUnits = [ "audiobookshelf" ];
    };
  };
}
