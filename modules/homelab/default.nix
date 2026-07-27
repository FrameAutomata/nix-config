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
    lanPorts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            tcp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [ ];
              description = "TCP ports this service needs reachable on the LAN interface";
            };
            udp = lib.mkOption {
              type = lib.types.listOf lib.types.port;
              default = [ ];
              description = "UDP ports this service needs reachable on the LAN interface";
            };
          };
        }
      );
      default = { };
      description = ''
        LAN-reachable ports, registered by the owning service modules — the
        same registration pattern as `homelab.nginx.internal`. All entries
        render into one `networking.firewall.interfaces.<lanInterface>`
        block, so the policy has a single site and a single audit command:
          nix eval .#nixosConfigurations.<host>.config.homelab.lanPorts

        Register here rather than setting a service's own `openFirewall`:
        upstream's flag drops ports into `networking.firewall.allowedTCPPorts`,
        which answers on every interface. Ports that genuinely must answer
        everywhere stay global and do NOT belong here — headscale.nix keeps
        two on purpose (80/443 for the public apex and ACME; tailscale's UDP
        41641, which needs WAN reachability for NAT traversal — moving it
        here would force every tailnet peer onto DERP relay).

        Know what interface scoping does and does not buy. It keeps ports off
        any other adapter and states intent — but on a single-NIC host one
        interface carries LAN traffic AND whatever the gateway routes in, so
        it cannot separate the two and is no substitute for the gateway's own
        inbound policy. If a host is ever multi-homed or deliberately exposed,
        source-address rules against lanCIDR/tailnetCIDR — the CIDRs nginx.nix
        already gates internal vhosts with — are the control to reach for.

        Those source rules are deferred deliberately (2026-07-27), not
        overlooked. Doing them properly needs networking.nftables.enable:
        `networking.firewall.extraInputRules` is nftables-only, and the
        iptables path (extraCommands) runs AFTER the generated rules, so an
        appended -A lands past the chain's refuse jump and silently never
        matches. Switching firewall backends on this box also touches
        tailscale's own rule management and the WireGuard netns — a bigger,
        riskier change than this registry, buying nothing while the gateway
        blocks inbound. TRIGGER to stop deferring: the Spectrum gateway going
        bridge mode behind our own router (already contemplated in the host's
        AdGuard DHCP note), or inbound IPv6 starting to route. On that day
        :53 is an open resolver and :445 is SMB on the internet. Cheap interim
        if that lands first, needing no backend switch: per-service source
        limits — samba `hosts allow`, AdGuard's own access list.

        The tailnet needs no entry *while headscale is enabled*: it is
        headscale.nix that sets `trustedInterfaces = [ "tailscale0" ]`, inside
        its own mkIf. Disable that module and the tailnet stops bypassing the
        firewall — including for remote SSH — so anything relying on the
        tailnet path must move here or the interface must be trusted
        elsewhere.
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
    # CLAUDE.md hard rule: never close port 22. Both routes to sshd are now
    # conditional — the LAN one is a registry entry a host has to remember to
    # make, the off-LAN one is headscale.nix's trustedInterfaces inside its
    # own mkIf — so losing both must fail the build, not the next login.
    # (A live rebuild would not even reveal it: firewall-iptables accepts
    # ESTABLISHED before the port rules, so the current session survives.)
    # "lo" is subtracted because nixpkgs trusts it unconditionally, which
    # would otherwise satisfy the check on a box reachable from nowhere.
    assertions = [
      {
        assertion =
          let
            lanTCP = lib.concatMap (p: p.tcp) (lib.attrValues cfg.lanPorts);
            trusted = lib.subtractLists [ "lo" ] config.networking.firewall.trustedInterfaces;
          in
          !config.networking.firewall.enable
          || !config.services.openssh.enable
          || trusted != [ ]
          # the global list counts too: a host may legitimately open :22
          # interface-independently (services.openssh.openFirewall = true),
          # which is MORE reachable than a lanPorts entry, not less
          || lib.all (p: lib.elem p config.networking.firewall.allowedTCPPorts)
            config.services.openssh.ports
          || lib.all (p: lib.elem p lanTCP) config.services.openssh.ports;
        message = ''
          homelab: sshd is enabled but nothing can reach it. No homelab.lanPorts
          entry covers services.openssh.ports (${
            lib.concatMapStringsSep ", " toString config.services.openssh.ports
          }) on ${cfg.lanInterface}, and no non-loopback interface is trusted.
          modules/common enables sshd but deliberately leaves reachability to
          the consuming config — register it there:
            homelab.lanPorts.ssh.tcp = config.services.openssh.ports;
        '';
      }
    ];
    # the one render site for the homelab.lanPorts registry (see its
    # description for what interface scoping does and doesn't buy)
    networking.firewall.interfaces.${cfg.lanInterface} = {
      # unique: two services registering the same port would otherwise emit
      # duplicate ACCEPT rules and make the registry a misleading audit
      allowedTCPPorts = lib.unique (lib.concatMap (p: p.tcp) (lib.attrValues cfg.lanPorts));
      allowedUDPPorts = lib.unique (lib.concatMap (p: p.udp) (lib.attrValues cfg.lanPorts));
    };
    users.groups.${cfg.group}.members = [ cfg.user ];
    # sticky, group-writable pool root: media-group members (roommates over
    # samba, service accounts like filebrowser) create freely but can't
    # rename or delete top-level entries they don't own — protects the
    # backup repo, .snapshots and the library roots from vandalism
    systemd.tmpfiles.rules = [ "d ${cfg.mounts.media} 1775 root ${cfg.group} -" ];
  };
}
