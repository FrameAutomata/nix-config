{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
    ../../modules/common
    ../../modules/common/nvidia.nix
    ../../modules/homelab
  ];

  networking.hostName = "wheezertbts";

  age.secrets.duckdns-token.file = ./secrets/duckdns-token.age;

  homelab = {
    baseDomain = "wheezertbts.duckdns.org";
    lanCIDR = "192.168.1.0/24";
    lanIP = "192.168.1.239";
    lanInterface = "enp3s0";
    tailnetIP = "100.64.0.1";
    timeZone = "America/Chicago";
    user = "wheezertbts";
    services = {
      adguard.enable = true;
      jellyfin.enable = true;
      audiobookshelf.enable = true;
      samba.enable = true;
      headscale.enable = true;
      duckdns.enable = true;
    };
  };

  # Keep this host's own resolution on public upstreams: once the router
  # hands out this box as the LAN DNS server, DHCP would otherwise point the
  # host at its own AdGuard — a bootstrap deadlock if AdGuard is down.
  networking.networkmanager.dns = "none";
  networking.nameservers = config.homelab.upstreamDNS;
  # ...and stop this box's own tailscale client from accepting headscale's
  # DNS push (which would put MagicDNS -> AdGuard-on-self in resolv.conf,
  # re-creating the self-dependency the pin above avoids)
  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];

  # Second LAN IP: the router's DHCP settings force two *different* DNS
  # entries, so both point at AdGuard via .239 and .240. NM profile keeps
  # DHCP for the primary address and adds .240 statically.
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = config.homelab.lanInterface;
      autoconnect = true;
      autoconnect-priority = 100; # beat the auto-generated "Wired connection 1"
    };
    ipv4 = {
      method = "auto"; # DHCP still provides .239 + routes
      address1 = "192.168.1.240/24";
    };
  };

  # Keep the apex pinned for THIS box even though AdGuard now serves split
  # DNS to clients: the host itself resolves via public upstreams (above), so
  # without the pin its own tailscale client would dial server_url at the WAN
  # IP and depend on router hairpin NAT — if that fails, this node (the
  # tailnet's subnet router AND DNS server) drops off the tailnet.
  networking.extraHosts = ''
    ${config.homelab.lanIP} ${config.homelab.baseDomain}
  '';

  users.users.${config.homelab.user} = {
    isNormalUser = true;
    description = "Wheezer the Band the Server";
    # video/render = GPU access for this host's NVIDIA card (modules/common/nvidia.nix)
    extraGroups = [ "networkmanager" "wheel" "video" "render" ];
    openssh.authorizedKeys.keys = [ (import ./keys.nix).admin ];
  };

  # This-host tooling, not base infrastructure (modules/common stays lean)
  environment.systemPackages = with pkgs; [
    claude-code
    gh
  ];

  # This host's GTX 1650 does the transcoding (driver stack: modules/common/nvidia.nix)
  services.jellyfin.hardwareAcceleration = {
    enable = true;
    type = "nvenc";
    device = "/dev/dri/renderD128";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "ththirlwall99@gmail.com";
  };

  # Legacy Surfshark OpenVPN — retired in Phase 5 (replaced by WireGuard netns).
  services.openvpn.servers.surfshark = {
    config = "config /etc/openvpn/surfshark.ovpn";
    autoStart = false;
    updateResolvConf = true;
  };

  system.stateVersion = "26.05"; # never change this
}
