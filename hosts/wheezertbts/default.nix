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
  age.secrets.surfshark-wg.file = ./secrets/surfshark-wg.age;
  age.secrets.vaultwarden-admin.file = ./secrets/vaultwarden-admin.age;

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
      prowlarr.enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      jellyseerr.enable = true;
      # Surfshark manual WireGuard (us-dal); the .age holds the keys, these
      # are the non-secret halves of the same config
      wireguard-netns = {
        enable = true;
        configFile = config.age.secrets.surfshark-wg.path;
        privateIP = "10.14.0.2/16";
        dnsIPs = [ "162.252.172.57" "149.154.159.92" ];
      };
      qbittorrent.enable = true;
      vaultwarden = {
        enable = true;
        # open registration during household onboarding — flip off once the
        # roommates have accounts (plan §8)
        allowSignups = true;
      };
      navidrome.enable = true;
      filebrowser.enable = true;
      homepage.enable = true;
      uptime-kuma.enable = true;
    };
    # The admin is a member automatically; roommate handles get appended to
    # household.members once agreed (plan §8).
    household.enable = true;
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

  # Fully static LAN addressing: this box IS the DHCP server (AdGuard,
  # below) since the Spectrum gateway can't hand out custom DHCP DNS, so it
  # cannot depend on any DHCP itself. .240 kept as a second address (both
  # router DNS slots pointed at AdGuard during the earlier attempt; harmless).
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = config.homelab.lanInterface;
      autoconnect = true;
      autoconnect-priority = 100; # beat the auto-generated "Wired connection 1"
    };
    ipv4 = {
      method = "manual";
      address1 = "${config.homelab.lanIP}/24";
      address2 = "192.168.1.240/24";
      gateway = "192.168.1.1";
    };
  };

  # AdGuard DHCP: written and tested, but DISABLED — the Spectrum gateway's
  # DHCP cannot be turned off (no LAN/DHCP controls; its "DNS Server" fields
  # reject LAN-side addresses outright), and two racing DHCP servers are
  # worse than none. Interim: per-device DNS -> 192.168.1.239.
  # Flip to true when the gateway goes bridge mode behind our own router.
  services.adguardhome.settings.dhcp = {
    enabled = false;
    interface_name = config.homelab.lanInterface;
    dhcpv4 = {
      gateway_ip = "192.168.1.1";
      subnet_mask = "255.255.255.0";
      range_start = "192.168.1.100";
      range_end = "192.168.1.200";
      lease_duration = 86400;
      # option 6 (DNS): both AdGuard addresses, explicitly
      options = [ "6 ips ${config.homelab.lanIP},192.168.1.240" ];
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

  system.stateVersion = "26.05"; # never change this
}
