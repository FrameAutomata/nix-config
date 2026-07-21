# AdGuard Home: LAN/tailnet DNS with split-DNS rewrites pointing
# *.baseDomain (and the apex) at this box's LAN IP, plus ad blocking.
{ config, lib, ... }:
let
  cfg = config.homelab.services.adguard;
  homelab = config.homelab;
in
{
  options.homelab.services.adguard.enable = lib.mkEnableOption "AdGuard Home DNS";

  config = lib.mkIf cfg.enable {
    services.adguardhome = {
      enable = true;
      host = "127.0.0.1"; # web UI reachable only through the internal vhost
      settings = {
        # explicit, not default-restating: with mutableSettings=true a web-UI
        # edit could otherwise silently move the DNS listener off 0.0.0.0
        dns.bind_hosts = [ "0.0.0.0" ];
        dns.upstream_dns = homelab.upstreamDNS;
        # cap the on-disk query log / stats (defaults keep 90 days —
        # continuous write I/O once the whole LAN resolves through this box)
        querylog.interval = "24h";
        statistics.interval = "24h";
        filtering.rewrites = [
          # split DNS: LAN/tailnet clients reach everything locally,
          # including Headscale on the apex.
          # enabled=true is REQUIRED: the yaml key defaults to false when
          # absent (verified live on 0.107.77).
          {
            domain = homelab.baseDomain;
            answer = homelab.lanIP;
            enabled = true;
          }
          {
            domain = "*.${homelab.baseDomain}";
            answer = homelab.lanIP;
            enabled = true;
          }
        ];
        filters = [
          {
            name = "AdGuard DNS filter";
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
            enabled = true;
            id = 1;
          }
        ];
      };
    };

    homelab.nginx.internal.adguard = {
      proxyPass = "http://127.0.0.1:${toString config.services.adguardhome.port}";
      dashboard = {
        name = "AdGuard Home";
        description = "DNS & ad blocking";
        icon = "adguard-home.svg";
        category = "Infrastructure";
      };
    };

    # When this box also runs headscale, point tailnet clients at AdGuard so
    # they get split DNS + blocking (overrides headscale.nix's mkDefault).
    services.headscale.settings.dns.nameservers.global =
      lib.mkIf config.homelab.services.headscale.enable [ homelab.tailnetIP ];

    # DNS on the LAN interface only (not the WAN-exposed default chain);
    # tailscale0 is a trusted interface, so tailnet clients already reach :53.
    # UDP 67 additionally when AdGuard is the LAN's DHCP server.
    networking.firewall.interfaces.${homelab.lanInterface} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts =
        [ 53 ] ++ lib.optional (config.services.adguardhome.settings.dhcp.enabled or false) 67;
    };
  };
}
