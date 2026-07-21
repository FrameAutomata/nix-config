# Headscale + its public vhost (ACME HTTP-01) + tailscale client.
# CRITICAL: roommates' remote access depends on this module. See CLAUDE.md hard rules.
{ config, lib, ... }:
let
  cfg = config.homelab.services.headscale;
  homelab = config.homelab;
in
{
  options.homelab.services.headscale.enable = lib.mkEnableOption "Headscale coordination server";

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      address = "0.0.0.0";
      port = 8080;
      settings = {
        server_url = "https://${homelab.baseDomain}";
        dns.base_domain = "internal";
        # mkDefault: overridden by adguard.nix (tailnet clients resolve
        # through AdGuard) when that service is enabled
        dns.nameservers.global = lib.mkDefault homelab.upstreamDNS;
      };
    };

    # keep the proxy layer's catch-all guarding the public apex vhost even if
    # all internal vhosts are ever disabled (mkDefault: a host may still
    # override, e.g. to front headscale with an external proxy)
    homelab.nginx.enable = lib.mkDefault true;

    services.tailscale = {
      enable = true;
      openFirewall = true; # opens the tailscale UDP port
      # "both" = client behaviors (rp_filter loose, preserved from the
      # original config) + server behaviors (IP forwarding, needed to route
      # the advertised LAN subnet). "server" alone would NOT loosen rp_filter.
      useRoutingFeatures = "both";
      # advertise the LAN so remote tailnet clients can reach the LAN IPs
      # that split DNS returns; route must be approved in headscale (§8)
      extraSetFlags = [ "--advertise-routes=${homelab.lanCIDR}" ];
    };

    services.nginx = {
      enable = true;
      virtualHosts.${homelab.baseDomain} = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://localhost:${toString config.services.headscale.port}";
          proxyWebsockets = true;
        };
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 80 443 ];
      trustedInterfaces = [ "tailscale0" ];
    };

    # a dead apex cert renewal takes roommates' remote access with it;
    # scheduled renewals run through the separate order-renew unit
    homelab.services.ntfy.notifyOnFailure = [
      "acme-${homelab.baseDomain}"
      "acme-order-renew-${homelab.baseDomain}"
    ];
  };
}
