# ntfy push notifications + the OnFailure plumbing: modules register their
# critical units in homelab.services.ntfy.notifyOnFailure and a failure
# pushes the unit's last log lines to the household topic.
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.services.ntfy;
  homelab = config.homelab;
  subdomain = "ntfy";
  port = 2586;
  notifyScript = pkgs.writeShellScript "homelab-notify" ''
    unit="$1"
    # journal tail goes via stdin, not argv — argv is world-readable in /proc
    ${pkgs.systemd}/bin/journalctl -u "$unit" -n 15 --no-pager -o cat \
      | ${pkgs.coreutils}/bin/tail -c 3800 \
      | ${pkgs.curl}/bin/curl -fsS -m 10 \
          -H "Title: ${config.networking.hostName}: $unit failed" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          --data-binary @- \
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
      description = ''
        Unit names (no .service suffix) that push a notification on failure
        — registered by the modules that own them. ACME units are the one
        exception, enrolled wholesale below: vhost modules create certs
        implicitly, so per-module registration would just duplicate
        nixpkgs' cert naming.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://${subdomain}.${homelab.baseDomain}";
        # explicit, not default-restating: the notify script and proxyPass
        # dial this address, so pin it against upstream default drift
        listen-http = "127.0.0.1:${toString port}";
        # rate-limit visitors by X-Forwarded-For instead of seeing only nginx
        behind-proxy = true;
      };
    };

    # every ACME cert gets failure alerts, for BOTH its unit families —
    # the renewal timers trigger acme-order-renew-<cert>, not acme-<cert>.
    # lego renews ~30 days before expiry, so a single failure is early
    # warning, not an emergency
    homelab.services.ntfy.notifyOnFailure = lib.concatMap (cert: [
      "acme-${cert}"
      "acme-order-renew-${cert}"
    ]) (lib.attrNames config.security.acme.certs);

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

    homelab.nginx.internal.${subdomain} = {
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
