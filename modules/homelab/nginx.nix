# Shared proxy plumbing: wildcard ACME cert (DNS-01 via DuckDNS) and the
# internal-vhost layer — <name>.<baseDomain> vhosts reachable only from
# LAN, tailnet, and localhost. The Headscale apex vhost (HTTP-01) lives in
# services/headscale.nix and is deliberately untouched by this module.
{ config, lib, ... }:
let
  homelab = config.homelab;
  cfg = config.homelab.nginx;
  certName = "wildcard-${homelab.baseDomain}";
in
{
  options.homelab.nginx = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.internal != { };
      defaultText = "true when any internal vhost is registered";
      description = ''
        Enable the shared proxy layer: internal vhosts, wildcard cert,
        catch-all vhost, and firewall openings. Any module exposing a public
        vhost (e.g. headscale) should set this so the catch-all keeps
        guarding it even with no internal vhosts left.
      '';
    };
    internal = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            proxyPass = lib.mkOption {
              type = lib.types.str;
              description = "Upstream URL to proxy to";
            };
            websockets = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Enable websocket proxying";
            };
          };
        }
      );
      default = { };
      description = "Internal vhosts served as <name>.<baseDomain>, allowlisted to LAN/tailnet/localhost";
    };
  };

  config = lib.mkIf cfg.enable {
    # Wildcard only — no apex SAN: DuckDNS allows one TXT record at a time,
    # and the apex is already covered by the Headscale vhost's HTTP-01 cert.
    # Only needed while internal vhosts exist; the catch-all is certless.
    security.acme.certs = lib.mkIf (cfg.internal != { }) {
      ${certName} = {
        domain = "*.${homelab.baseDomain}";
        dnsProvider = "duckdns";
        environmentFile = homelab.duckdnsTokenFile;
        group = "nginx";
      };
    };

    # The proxy layer owns its own ports (headscale.nix keeping a copy is a
    # harmless list merge).
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    services.nginx = {
      enable = true;
      virtualHosts =
        lib.mapAttrs' (
          name: vh:
          lib.nameValuePair "${name}.${homelab.baseDomain}" {
            forceSSL = true;
            useACMEHost = certName;
            locations."/" = {
              proxyPass = vh.proxyPass;
              proxyWebsockets = vh.websockets;
              # Host/X-Real-IP/X-Forwarded-* headers — without these, upstreams
              # see every client as 127.0.0.1 (breaks Jellyfin per-IP policies
              # and lockouts). Per-location so the apex vhost stays untouched.
              recommendedProxySettings = true;
            };
            extraConfig = ''
              allow ${homelab.lanCIDR};
              allow ${homelab.tailnetCIDR};
              allow ${homelab.tailnetCIDRv6};
              allow 127.0.0.1;
              allow ::1;
              deny all;
            '';
          }
        ) cfg.internal
        // {
          # default_server catch-all for unrecognized Host headers: refuse the
          # TLS handshake outright (no cert served to scanners) and close
          # plain-HTTP without a response. Exact server_name matches (the
          # Headscale apex vhost and its ACME challenge path) always beat
          # default_server, so nothing legitimate is shadowed.
          "catchall.invalid" = {
            default = true;
            rejectSSL = true;
            extraConfig = "return 444;";
          };
        };
    };
  };
}
