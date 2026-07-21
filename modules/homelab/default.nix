{ config, lib, ... }:
let
  cfg = config.homelab;
  mkSecretOption = import ./secret-option.nix { inherit lib config; };
in
{
  imports = [
    ./nginx.nix
    ./household.nix
    ./onboard.nix
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
    lanIP = lib.mkOption {
      type = lib.types.str;
      description = "This host's LAN IP (split-DNS rewrite target)";
    };
    lanInterface = lib.mkOption {
      type = lib.types.str;
      description = "LAN network interface name (for interface-scoped firewall rules)";
    };
    tailnetIP = lib.mkOption {
      type = lib.types.str;
      description = ''
        This host's tailnet IP (assigned by headscale at registration —
        verify with `ip addr show tailscale0` and re-check after any
        re-registration; tailnet clients use it as their DNS server, so a
        stale value silently breaks all tailnet DNS)
      '';
    };
    upstreamDNS = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "9.9.9.9" # Quad9
        "1.1.1.1" # Cloudflare
      ];
      description = "Public DNS upstreams, used by AdGuard and as the host's own bootstrap resolvers";
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
    duckdnsTokenFile = mkSecretOption {
      secret = "duckdns-token";
      optionPath = "homelab";
      hint = "an EnvironmentFile with DUCKDNS_TOKEN=..., used by the DuckDNS updater and by ACME DNS-01 for the wildcard cert";
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
    # sticky, group-writable pool root: media-group members (roommates over
    # samba, service accounts like filebrowser) create freely but can't
    # rename or delete top-level entries they don't own — protects the
    # backup repo, .snapshots and the library roots from vandalism
    systemd.tmpfiles.rules = [ "d ${cfg.mounts.media} 1775 root ${cfg.group} -" ];
  };
}
