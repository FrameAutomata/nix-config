# ntfy push notifications + the OnFailure plumbing: modules register their
# critical units in homelab.services.ntfy.notifyOnFailure and a failure
# pushes the unit's last log lines to the household topic.
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.services.ntfy;
  homelab = config.homelab;
  port = 2586;
  notifyScript = pkgs.writeShellScript "homelab-notify" ''
    unit="$1"
    ${pkgs.curl}/bin/curl -fsS -m 10 \
      -H "Title: ${config.networking.hostName}: $unit failed" \
      -H "Priority: high" \
      -H "Tags: rotating_light" \
      --data-binary "$(${pkgs.systemd}/bin/journalctl -u "$unit" -n 15 --no-pager -o cat | ${pkgs.coreutils}/bin/tail -c 3800)" \
      "http://127.0.0.1:${toString port}/${cfg.topic}"
  '';
in
{
  options.homelab.services.ntfy = {
    enable = lib.mkEnableOption "ntfy push notification server";
    topic = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = "Topic failure alerts publish to; phones subscribe at https://ntfy.<baseDomain>/<topic>";
    };
    notifyOnFailure = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Unit names (no .service suffix) that push a notification on failure — registered by the modules that own them";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.${homelab.baseDomain}";
        listen-http = "127.0.0.1:${toString port}";
        # rate-limit visitors by X-Forwarded-For instead of seeing only nginx
        behind-proxy = true;
      };
    };

    # No auth: anyone who can reach the vhost (LAN/tailnet — household)
    # can read/publish topics. Add ntfy ACLs before ever exposing this wider.
    systemd.services = {
      "homelab-notify@" = {
        description = "Failure notification for %i";
        # if ntfy itself is down the push just fails; nothing depends on it
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${notifyScript} %i";
        };
      };
    }
    // lib.genAttrs cfg.notifyOnFailure (unit: {
      onFailure = [ "homelab-notify@${unit}.service" ];
    });

    homelab.nginx.internal.ntfy = {
      proxyPass = "http://127.0.0.1:${toString port}";
      # subscriptions stream over websocket/long-poll
      websockets = true;
      dashboard = {
        name = "ntfy";
        description = "Push notifications";
        icon = "ntfy.svg";
        category = "Infrastructure";
      };
    };
  };
}
