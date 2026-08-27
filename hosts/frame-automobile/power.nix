# Battery / idle-power tuning for the Acer Aspire A14-52MT
# (Core Ultra 5 226V "Lunar Lake", BE200 Wi-Fi 7).
#
# Host-local rather than a modules/laptop/: every value here was measured on
# this chassis, and there is one laptop in this repo. Same reasoning as
# hosts/frame-automata/filesystems.nix.

{ config, pkgs, ... }:

{
  # Kept over TLP: Plasma's power-profile switcher is a PPD client and
  # disappears if TLP masks it. PPD handles CPU; the rest of this file covers
  # the device-level tuning PPD doesn't do on this machine.
  services.power-profiles-daemon.enable = true;

  # Reacts before the firmware trip points, avoiding boost-then-throttle cycles.
  services.thermald.enable = true;

  # Closing the lid suspends first, then hibernates after a delay. This is the
  # payoff for the swapfile in default.nix: /sys/power/mem_sleep offers only
  # s2idle on this chassis, no S3, so a closed lid keeps drawing enough to
  # matter across a night. Waking on an RTC alarm to write the image turns the
  # tail of a long close into ~zero draw, while a short close still resumes
  # instantly from RAM.
  #
  # 30min is the tradeoff point: longer than a lid-close that is really a pause
  # (meeting, lunch, walking between rooms), shorter than the stretch of an
  # overnight close where s2idle is just burning charge for nothing.
  systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";

  # This only reaches the lid when nothing holds logind's handle-lid-switch
  # inhibitor -- the SDDM login screen, a TTY, a session that died. Inside
  # Plasma it is dead config: PowerDevil takes that inhibitor as a *block* and
  # owns the lid itself (`systemd-inhibit --list` shows it). The matching
  # setting there is per-user Plasma state, and this repo runs no home-manager,
  # so it stays MANUAL -- see the README. HibernateDelaySec above governs the
  # suspend-to-hibernate gap either way, whoever invokes it.
  #
  # External power stays on plain suspend: hibernating a plugged-in laptop
  # spends the resume latency to save a charge that is not being drawn down.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend";
  };

  # Firmware already had ASPM optimal; this only avoids regressing it. Measured
  # on the SSD link: "powersave" turns the L1.1/L1.2 substates OFF, and only
  # "powersupersave" reproduces firmware's L1.2+ state. Not pcie_aspm=force —
  # known to hang consumer laptops, and the links are already OS-controlled.
  boot.kernelParams = [ "pcie_aspm.policy=powersupersave" ];

  # 11 devices (incl. Wi-Fi and the SSD) shipped with runtime PM off. A device
  # that never suspends keeps the whole SoC package out of deep idle.
  # If something misbehaves, exclude it by PCI ID rather than dropping the rule.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"

    # USB too, except HID -- autosuspending keyboards/mice causes input lag.
    # (This is why powerManagement.powertop.enable isn't used: --auto-tune
    # suspends input devices indiscriminately.)
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", \
      ATTR{bInterfaceClass}!="03", ATTR{power/control}="auto"
  '';

  networking.networkmanager.wifi.powersave = true;

  boot.extraModprobeConfig = ''
    # power_scheme=3 is iwlmvm's low-power mode. If Wi-Fi feels sluggish or
    # drops on weak signal, set it back to 2 -- likeliest culprit in this file.
    options iwlwifi power_save=1
    options iwlmvm power_scheme=3

    options snd_hda_intel power_save_controller=Y
  '';

  # No WWAN modem in this machine (confirmed via lspci); NetworkManager pulls
  # ModemManager in by default.
  systemd.services.ModemManager.enable = false;

  # The weekly rebuild, and the store maintenance that trails it, cost 10-15%
  # of a charge. All three skip on battery and wait for their next window
  # rather than spending it. gc and optimise come from modules/workstation;
  # nixos-upgrade from this host's default.nix.
  systemd.services.nixos-upgrade.unitConfig.ConditionACPower = true;
  systemd.services.nix-gc.unitConfig.ConditionACPower = true;
  systemd.services.nix-optimise.unitConfig.ConditionACPower = true;

  # For re-diagnosing later: powertop (Tunables / Device stats tabs),
  # turbostat --show PkgWatt,Busy%,CPU%c7, lspci -vv | grep -i aspm.
  # pciutils/usbutils already come from modules/workstation.
  environment.systemPackages = with pkgs; [
    powertop
    config.boot.kernelPackages.turbostat
  ];
}
