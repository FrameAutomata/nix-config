# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "wheezer-the-band-the-server"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  services.xrdp.enable = true;
  services.xrdp.defaultWindowManager = "${pkgs.writeShellScript "start-plasma-xrdp" ''
     export KWIN_COMPOSE=N
     exec startplasma-x11 > /tmp/plasma-xrdp.log 2>&1
  ''}";
  services.xrdp.openFirewall = true;


  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."wheezertbts" = {
    isNormalUser = true;
    description = "Wheezer the Band the Server";
    extraGroups = [ "networkmanager" "wheel" "video" "render"];
    packages = with pkgs; [
      kdePackages.kate
    #  thunderbird
    ];
  };

  users.users."wheezertbts".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPp3lCoxw+RdLFkALHGG+zmHw1NkMMaV8bQ7Km2yIX7 corbi@DESKTOP-CJ3RO7R"
  ];


  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable Nix Commands and Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  wget
  xclip
  config.services.headscale.package
  claude-code
  git
  gh
  tmux
  ];

  # Adding Nvidia driver support and allowing for X11 video rendering
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
     modesetting.enable = true;
     open = false;
     package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  services.udev.extraRules = ''
     KERNEL=="card0", SUBSYSTEM=="drm", TAG+="uaccess"
  '';

  # RAID1 mounting
  fileSystems."/mnt/media" = {
     device = "/dev/disk/by-label/media";
     fsType = "btrfs";
  };
  
  # Jellyfin
  services.jellyfin = {
     enable = true;
     openFirewall = true;
     hardwareAcceleration = {
       enable = true;
       type = "nvenc";
       device = "/dev/dri/renderD128";
     };
  };
  
  # Audiobookshelf
  services.audiobookshelf = {
    enable = true;
    openFirewall = true;
    host = "0.0.0.0"; # defaults to localhost-only, which blocks every other device
  };

  users.groups.media.members = [ "wheezertbts" "jellyfin" "audiobookshelf" ];
  users.users.jellyfin.extraGroups = [ "media" ];
  users.users.audiobookshelf.extraGroups = [ "media" ];

  # Samba
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "security" = "user";
      };
      media = {
        path = "/mnt/media";
        "valid users" = "wheezertbts";
        "public" = "no";
        "writeable" = "yes";
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "0775";
      };
    };
  };
  
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # OpenVPN/Surfshark
  services.openvpn.servers.surfshark = {
    config = "config /etc/openvpn/surfshark.ovpn";
    autoStart = false;
    updateResolvConf = true;
  };
  
  # DuckDNS
  systemd.services.duckdns = {
    description = "Update DuckDNS IP";
    script = ''
      TOKEN=$(cat /etc/duckdns/token)
      ${pkgs.curl}/bin/curl -fsS "https://www.duckdns.org/update?domains=wheezertbts&token=$TOKEN&ip="
    '';
    serviceConfig.Type = "oneshot";
  };

  systemd.timers.duckdns = {
    description = "Update DuckDNS IP periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };

  networking.extraHosts = ''
    192.168.1.239 wheezertbts.duckdns.org
  '';

  # Headscale
  services.headscale = {
    enable = true;
    address = "0.0.0.0";
    port = 8080;
    settings = {
      server_url = "https://wheezertbts.duckdns.org";
      dns.base_domain = "internal";
      dns.nameservers.global = [ "1.1.1.1" "8.8.8.8" ];
    };
  };
  
  # Tailscale Client
  services.tailscale.enable = true;

  services.nginx = {
    enable = true;
    virtualHosts."wheezertbts.duckdns.org" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:8080";
        proxyWebsockets = true;
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "ththirlwall99@gmail.com"; # replace with a real address — Let's Encrypt sends renewal notices here
  };

  #  
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Allowed ports and interfaces for Firewall
  networking.firewall = {
    allowedTCPPorts = [ 22 80 443 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
    trustedInterfaces = [ "tailscale0" ];
  };
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "26.05"; # Did you read the comment?

}
