{ config, lib, ... }:
let
  cfg = config.homelab;
in
{
  imports = [
    ./nginx.nix
    ./services
  ];

  options.homelab = {
    baseDomain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain; service vhosts hang off it as <name>.<baseDomain>";
    };
    lanCIDR = lib.mkOption {
      type = lib.types.str;
      description = "LAN subnet, allowed by internal-vhost access control";
    };
    tailnetCIDR = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
      description = "Tailnet IPv4 subnet, allowed by internal-vhost access control";
    };
    tailnetCIDRv6 = lib.mkOption {
      type = lib.types.str;
      default = "fd7a:115c:a1e0::/48";
      description = "Tailnet IPv6 ULA prefix (headscale assigns dual-stack by default), allowed by internal-vhost access control";
    };
    duckdnsTokenFile = lib.mkOption {
      type = lib.types.path;
      default =
        (config.age.secrets.duckdns-token or (throw ''
          homelab: the host must declare age.secrets.duckdns-token
          (an EnvironmentFile with DUCKDNS_TOKEN=...), used by the DuckDNS
          updater and by ACME DNS-01 for the wildcard cert
        '')).path;
      defaultText = "config.age.secrets.duckdns-token.path";
      description = "EnvironmentFile containing DUCKDNS_TOKEN=...";
    };
    mounts.media = lib.mkOption {
      # a string, not types.path: the value is used as a mount point / share
      # path, and a path literal here would be copied into the nix store
      type = lib.types.str;
      default = "/mnt/media";
      description = "Bulk media/data mount";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "Admin user; set explicitly by the host to keep the coupling visible";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared group for media services";
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      description = "Host time zone";
    };
  };

  config = {
    time.timeZone = cfg.timeZone;
    users.groups.${cfg.group}.members = [ cfg.user ];
  };
}
