{ pkgs, ... }:

let
  site = import ../../site.nix;
in

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common
    ../../modules/common/amdgpu.nix
    ../../modules/workstation
    ../../modules/homelab-client
  ];

  networking.hostName = "frame-automata";
  time.timeZone = site.timeZone;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  users.users.frame-automata = {
    isNormalUser = true;
    description = "Thomas"; # GECOS, shown on the SDDM login screen
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # modules/common runs sshd and leaves reachability to the host. Nothing is
  # opened: this is a personal desktop and the tailnet carries household
  # devices. To reach it from the laptop, give the user an
  # openssh.authorizedKeys.keys entry and open :22 on tailscale0 only.
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  # Pin the apex to the LAN IP. A client not yet on the tailnet cannot use
  # AdGuard's split DNS, so it resolves this to the WAN address and depends on
  # router hairpin NAT — which is what hangs `tailscale up` on a first join.
  # hosts/wheezertbts pins the same name for the same reason.
  networking.extraHosts = "${site.lanIP} ${site.baseDomain}";

  homelabClient = {
    enable = true;
    notifyOnFailure = [ "nixos-upgrade" ];
    mounts = {
      enable = true;
      owner = "frame-automata";
      # "wheezertbts" is the admin's private area — household.nix names each
      # member's share after their handle and includes the admin.
      shares = [
        "media"
        "shared"
        "wheezertbts"
      ];
      # Hand-created, not agenix: this host has no host key in secrets.nix, so
      # it cannot decrypt. Enroll its /etc/ssh/ssh_host_ed25519_key.pub in
      # keys.nix after first boot to fix that properly (see README).
      credentialsFile = "/etc/samba/credentials-homelab";
    };
  };

  # package = overrides the module default, which would otherwise build from
  # claude-desktop's own nixpkgs input rather than this host's.
  programs.claude-desktop = {
    enable = true;
    package = pkgs.claude-desktop;
    cowork.kvmUsers = [ "frame-automata" ];
  };

  # Weekly update from whatever is committed, so deploying is pushing.
  # upgrade = false is required, not cosmetic: --upgrade is added whenever
  # `channel` is null, and this host has no channels to refresh.
  system.autoUpgrade = {
    enable = true;
    flake = "github:FrameAutomata/nix-config#frame-automata";
    operation = "switch";
    upgrade = false;
    dates = "Mon 02:00";
    persistent = true;
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  environment.systemPackages = with pkgs; [
    # editors / terminal
    neovim
    zed-editor
    ghostty
    kdePackages.kate
    # browsers
    vivaldi
    brave
    # chat
    discord
    # dev + homelab admin
    gh
    claude-code
    headroom # pkgs/headroom — context-compression proxy, `headroom wrap claude`
  ];

  system.stateVersion = "26.05"; # never change this
}
