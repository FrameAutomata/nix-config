{ config, lib, ... }:
let
  cfg = config.homelab.services.sonarr;
in
{
  options.homelab.services.sonarr.enable = lib.mkEnableOption "Sonarr TV series manager";

  config = lib.mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      group = config.homelab.group;
    };

    homelab.services.backup = {
      statePaths = [ "/var/lib/sonarr" ];
      quiesceUnits = [ "sonarr" ];
    };

    homelab.nginx.internal.sonarr = {
      proxyPass = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
      dashboard = {
        name = "Sonarr";
        description = "TV automation";
        icon = "sonarr.svg";
        category = "Downloads";
      };
    };
  };
}
