{ config, lib, ... }:
let
  cfg = config.homelab.services.lidarr;
in
{
  options.homelab.services.lidarr.enable = lib.mkEnableOption "Lidarr music manager";

  config = lib.mkIf cfg.enable {
    services.lidarr = {
      enable = true;
      group = config.homelab.group;
    };

    homelab.services.backup = {
      statePaths = [ "/var/lib/lidarr" ];
      quiesceUnits = [ "lidarr" ];
    };

    homelab.nginx.internal.lidarr = {
      proxyPass = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
      dashboard = {
        name = "Lidarr";
        description = "Music automation";
        icon = "lidarr.svg";
        category = "Downloads";
      };
    };
  };
}
