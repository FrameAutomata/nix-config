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
        dns.nameservers.global = [ "1.1.1.1" "8.8.8.8" ];
      };
    };

    # keep the proxy layer's catch-all guarding the public apex vhost even if
    # all internal vhosts are ever disabled (mkDefault: a host may still
    # override, e.g. to front headscale with an external proxy)
    homelab.nginx.enable = lib.mkDefault true;

    services.tailscale = {
      enable = true;
      openFirewall = true; # opens the tailscale UDP port
      useRoutingFeatures = "client"; # sets checkReversePath = "loose"
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
  };
}
