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
    homelab.nginx.internal.sonarr = {
      proxyPass = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
    };
  };
}
