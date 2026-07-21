# SMART health for the two 12 TB spinners + the SSD. Note: pulls in a
# local InfluxDB 2 instance (scrutiny's storage backend) — the biggest
# RAM consumer of the monitoring stack on this 8 GB box.
{ config, lib, ... }:
let
  cfg = config.homelab.services.scrutiny;
in
{
  options.homelab.services.scrutiny.enable = lib.mkEnableOption "Scrutiny disk health dashboard";

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      settings.web.listen = {
        host = "127.0.0.1";
        # upstream default is 8080, which belongs to Headscale on this host
        port = 8085;
      };
      collector.enable = true;
    };

    homelab.nginx.internal.disks = {
      proxyPass = "http://127.0.0.1:${toString config.services.scrutiny.settings.web.listen.port}";
      dashboard = {
        name = "Scrutiny";
        description = "Disk health (SMART)";
        icon = "scrutiny.svg";
        category = "Infrastructure";
      };
    };
  };
}
