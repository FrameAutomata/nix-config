{ config, lib, ... }:
let
  cfg = config.homelab.services.radarr;
in
{
  options.homelab.services.radarr.enable = lib.mkEnableOption "Radarr movie manager";

  config = lib.mkIf cfg.enable {
    services.radarr = {
      enable = true;
      group = config.homelab.group;
    };
    homelab.nginx.internal.radarr = {
      proxyPass = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
      dashboard = {
        name = "Radarr";
        description = "Movie automation";
        icon = "radarr.svg";
        category = "Downloads";
      };
    };
  };
}
