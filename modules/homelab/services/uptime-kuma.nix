{ config, lib, ... }:
let
  cfg = config.homelab.services.uptime-kuma;
in
{
  options.homelab.services.uptime-kuma.enable = lib.mkEnableOption "Uptime Kuma status monitor";

  config = lib.mkIf cfg.enable {
    # upstream defaults bind 127.0.0.1:3001; monitors are configured in its UI
    services.uptime-kuma.enable = true;

    homelab.nginx.internal.status = {
      proxyPass = "http://127.0.0.1:${config.services.uptime-kuma.settings.PORT}";
      # the UI is socket.io — dead without websocket upgrade
      websockets = true;
      dashboard = {
        name = "Uptime Kuma";
        description = "Service uptime monitor";
        icon = "uptime-kuma.svg";
        category = "Infrastructure";
      };
    };
  };
}
