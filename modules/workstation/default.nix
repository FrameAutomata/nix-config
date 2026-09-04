# Interactive-machine base: desktop session, audio, bluetooth, gaming, and
# store maintenance. Host-agnostic — a host adds hardware, users, and its own
# system.autoUpgrade source.
#
# This is every interactive machine, including the ones this repo is not
# administered from. Thomas's editor/terminal/CLI layer is
# modules/workstation/dev-tools.nix, and his Traceway databases are
# dev-databases.nix; both are imported only by the two hosts he works on.
{ pkgs, ... }:

{
  # Audio is modules/common/audio.nix rather than inline: the server's TV seat
  # (hosts/wheezertbts/tv.nix) wants the same PipeWire stack and none of the
  # rest of this file.
  imports = [ ../common/audio.nix ];

  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

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

  # Stated beside Steam rather than in modules/common/audio.nix, the same way
  # intel-gpu.nix states hardware.graphics.enable32Bit: what needs a 32-bit
  # audio path is Proton/Wine, not speakers. Keeping it here is what keeps an
  # i686 PipeWire closure off the server, which shares that audio module.
  services.pipewire.alsa.support32Bit = true;

  # The app set every workstation gets, admin machine or not: a browser, an
  # office suite, a GUI text editor, chat, and the hardware/gaming bits.
  # Anything that is only useful when you also deploy this repo belongs in
  # a dev-*.nix layer — that boundary is what lets a third workstation share
  # this file.
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
