# Interactive-machine base: desktop session, audio, bluetooth, gaming, and
# store maintenance. Host-agnostic — a host adds hardware, users, and its own
# system.autoUpgrade source.
#
# This is every interactive machine, including the ones this repo is not
# administered from. Thomas's editor/terminal/CLI layer is
# modules/workstation/dev.nix, imported only by the two hosts he works on.
{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # powerOnBoot and Policy.AutoEnable are left at their defaults — both are
  # already true, and AutoEnable is derived from powerOnBoot upstream.
  hardware.bluetooth = {
    enable = true;
    # Battery charge of connected devices, on adapters that support it.
    settings.General.Experimental = true;
  };

  # These openFirewall flags land in the GLOBAL allowedTCP/UDPPorts, so the
  # Steam listeners answer on tailscale0 too — every tailnet peer can reach
  # them, not just the LAN. Interface-scoping needs the per-host LAN
  # interface name, so it is left to a host that cares.
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    protontricks.enable = true;
  };
  programs.gamemode.enable = true;

  # The app set every workstation gets, admin machine or not: a browser, an
  # office suite, a GUI text editor, chat, and the hardware/gaming bits.
  # Anything that is only useful when you also deploy this repo belongs in
  # dev.nix — that boundary is what lets a third workstation share this file.
  environment.systemPackages = with pkgs; [
    # hardware / gaming
    mangohud
    pciutils
    usbutils
    # editors
    kdePackages.kate
    # browsers
    vivaldi
    brave
    # chat
    discord
    # productivity
    libreoffice-qt
    hunspell
    hunspellDicts.en_US
    hyphenDicts.en_US
  ];

  # Nothing reclaims the store otherwise, and autoUpgrade adds a generation a
  # week. optimise hardlinks identical files between store paths.
  #
  # Explicit days rather than "weekly": that resolves to Mon 00:00 for every
  # timer, so gc, optimise and the upgrade would share one window — with
  # optimise hashing and hardlinking paths gc is about to delete.
  nix.gc = {
    automatic = true;
    dates = "Mon 04:00";
    persistent = true;
    randomizedDelaySec = "30min";
    options = "--delete-older-than 30d";
  };
  nix.optimise = {
    automatic = true;
    dates = "Wed 03:00";
    persistent = true;
    randomizedDelaySec = "30min";
  };
}
