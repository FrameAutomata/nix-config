# DuckDNS IP updater. The token comes from an agenix EnvironmentFile
# (DUCKDNS_TOKEN=...) declared by the host as age.secrets.duckdns-token.
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
      # DuckDNS answers HTTP 200 with body "KO" on a bad/empty token, so
      # curl -f alone cannot detect failure — check the body explicitly.
      script = ''
        resp=$(${pkgs.curl}/bin/curl -fsS "https://www.duckdns.org/update?domains=${subdomain}&token=$DUCKDNS_TOKEN&ip=")
        echo "$resp"
        [ "$resp" = "OK" ]
      '';
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile =
          (config.age.secrets.duckdns-token or (throw ''
            homelab.services.duckdns: the host must declare
            age.secrets.duckdns-token (an EnvironmentFile with DUCKDNS_TOKEN=...)
          '')).path;
      };
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
