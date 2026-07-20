# DuckDNS IP updater. Token file moves to agenix in Phase 2.
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.services.duckdns;
  # DuckDNS updates are keyed on the subdomain, i.e. the first label of baseDomain
  subdomain = lib.head (lib.splitString "." config.homelab.baseDomain);
in
{
  options.homelab.services.duckdns.enable = lib.mkEnableOption "DuckDNS IP updater";

  config = lib.mkIf cfg.enable {
    systemd.services.duckdns = {
      description = "Update DuckDNS IP";
      script = ''
        TOKEN=$(cat /etc/duckdns/token)
        ${pkgs.curl}/bin/curl -fsS "https://www.duckdns.org/update?domains=${subdomain}&token=$TOKEN&ip="
      '';
      serviceConfig.Type = "oneshot";
    };

    systemd.timers.duckdns = {
      description = "Update DuckDNS IP periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
