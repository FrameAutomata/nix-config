# Interactive-machine base: desktop session, audio, bluetooth, gaming, and
# store maintenance. Host-agnostic — a host adds hardware, users, and its own
# system.autoUpgrade source.
{ config, pkgs, ... }:

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

  # The shared workstation app set. Both hosts run the same Plasma/gaming/Claude
  # stack, so this lives here rather than being duplicated in each host tree — a
  # host's own systemPackages carries only what is true of that machine alone.
  # claude-code and headroom come from the overlays the flake's `shared` module
  # applies, so this module is only complete when composed with it.
  environment.systemPackages = with pkgs; [
    # hardware / gaming
    mangohud
    pciutils
    usbutils
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
    # productivity
    libreoffice-qt
    hunspell
    hunspellDicts.en_US
    hyphenDicts.en_US
    # dev + homelab admin
    gh
    claude-code
    headroom # pkgs/headroom — context-compression proxy, `headroom wrap claude`
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

  # Weekly check for a newer NixOS stable release. NOTIFIES rather than
  # switching: there is no rolling "nixos-stable" alias to follow, and a
  # release hop carries breaking changes documented in the release notes.
  # A user service so the notification reaches the Plasma session.
  systemd.user.services.nixos-release-check = {
    description = "Check whether a newer NixOS stable release is available";
    startAt = "weekly";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
      curl
      gnugrep
      gnused
      coreutils
      libnotify
    ];
    script = ''
      set -eu
      current="${config.system.nixos.release}"
      newest=$(curl -sf --max-time 30 "https://nix-channels.s3.amazonaws.com/?delimiter=/" \
        | grep -oE 'nixos-[0-9]{2}\.[0-9]{2}/' \
        | sed 's#nixos-##; s#/##' \
        | sort -V | tail -1) || exit 0
      [ -n "$newest" ] || exit 0
      if [ "$newest" != "$current" ] \
         && [ "$(printf '%s\n%s\n' "$current" "$newest" | sort -V | tail -1)" = "$newest" ]; then
        echo "NixOS $newest is available (running $current)"
        # || true: no notification daemon (early login, SDDM greeter's own user
        # manager) must not fail the unit under set -e
        notify-send -u normal -i system-software-update \
          "NixOS $newest is available" \
          "Running $current. Read the release notes, then move this host to nixos-$newest and rebuild." || true
      else
        echo "Up to date: running $current, newest stable is $newest"
      fi
    '';
  };

  systemd.user.timers.nixos-release-check.timerConfig = {
    Persistent = true;
    RandomizedDelaySec = "6h";
  };
}
