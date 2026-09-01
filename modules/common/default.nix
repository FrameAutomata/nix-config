# Host-agnostic base: boot, locale, nix settings, admin user, ssh, base packages.
# Must never import or assume anything from modules/homelab.
{ pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

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

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    tmux
  ];

  # Running the daemon is base infrastructure; which interfaces answer on :22
  # is per-host topology, so the consuming config owns the firewall opening.
  # NOTE this means a config importing only this module has a running but
  # unreachable sshd — opening :22 is that config's job.
  services.openssh.enable = true;
  # upstream defaults this to true, which would put 22 on the GLOBAL
  # allowedTCPPorts (every interface) behind our back
  services.openssh.openFirewall = false;
}
