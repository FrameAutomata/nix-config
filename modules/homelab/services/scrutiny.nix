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
    };

    # InfluxDB idles at hundreds of MB for one SMART sample/day per disk —
    # cap it so compaction spikes can't squeeze the box. Guarded: with
    # influxdb.enable = false (external instance) this block would be the
    # only influxdb2 definition and produce a broken ExecStart-less unit.
    systemd.services.influxdb2 = lib.mkIf config.services.scrutiny.influxdb.enable {
      environment.GOMEMLIMIT = "300MiB";
      serviceConfig = {
        MemoryHigh = "384M";
        MemoryMax = "512M";
      };
    };

    # a compaction spike above MemoryMax means a cgroup OOM-kill loop that
    # Restart=on-failure hides until the rate limit trips — make it visible
    homelab.services.ntfy.notifyOnFailure = lib.optional config.services.scrutiny.influxdb.enable "influxdb2";

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
