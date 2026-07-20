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
    timeZone = "America/Chicago";
    user = "wheezertbts";
    services = {
      jellyfin.enable = true;
      audiobookshelf.enable = true;
      samba.enable = true;
      headscale.enable = true;
      duckdns.enable = true;
    };
  };

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

  # Split-DNS stopgap so LAN clients resolve the domain locally.
  # Removed in Phase 4 when AdGuard Home takes over DNS.
  networking.extraHosts = ''
    192.168.1.239 ${config.homelab.baseDomain}
  '';

  # Legacy Surfshark OpenVPN — retired in Phase 5 (replaced by WireGuard netns).
  services.openvpn.servers.surfshark = {
    config = "config /etc/openvpn/surfshark.ovpn";
    autoStart = false;
    updateResolvConf = true;
  };

  system.stateVersion = "26.05"; # never change this
}
