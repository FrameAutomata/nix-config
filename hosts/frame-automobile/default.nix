{ pkgs, ... }:

let
  site = import ../../site.nix;
in

{
  imports = [
    ./hardware-configuration.nix
    ./power.nix
    ../../modules/common
    ../../modules/common/intel-gpu.nix
    ../../modules/workstation
    ../../modules/homelab-client
  ];

  networking.hostName = "frame-automobile";
  time.timeZone = site.timeZone;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # The scan that produced hardware-configuration.nix ran with nothing plugged
  # in, so it dropped the USB-storage pair the install-time scan had. Root is on
  # NVMe and does not need them; they keep a USB disk visible to a rescue
  # initrd. Stated here rather than hand-editing the generated file.
  boot.initrd.availableKernelModules = [
    "usb_storage"
    "sd_mod"
  ];

  users.users.frame-automobile = {
    isNormalUser = true;
    description = "Thomas"; # GECOS, shown on the SDDM login screen
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  # modules/common runs sshd and leaves reachability to the host. Nothing is
  # opened, and this host roams onto networks the desktop never sees, so
  # nothing should be.
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  # Pin the apex to the LAN IP. A client not yet on the tailnet cannot use
  # AdGuard's split DNS, so it resolves this to the WAN address and depends on
  # router hairpin NAT — which is what hangs `tailscale up` on a first join.
  # hosts/wheezertbts and hosts/frame-automata pin the same name.
  networking.extraHosts = "${site.lanIP} ${site.baseDomain}";

  # Grabs the built-in keyboard so the Copilot key can be remapped. `settings`
  # is left at its default empty set, so every key currently passes through
  # unchanged — the remap itself is still to be written. `keyd monitor` prints
  # the key names to write it with.
  services.keyd = {
    enable = true;
    keyboards.default.ids = [ "0001:0001:093d12dc" ];
  };

  # No mounts: this host has no key in keys.nix, so it cannot decrypt a
  # samba-client secret of its own the way frame-automata does. Enrolling one
  # is what that would take — see the laptop section of the README.
  homelabClient = {
    enable = true;
    notifyOnFailure = [ "nixos-upgrade" ];
  };

  # package = overrides the module default, which would otherwise build from
  # claude-desktop's own nixpkgs input rather than this host's.
  programs.claude-desktop = {
    enable = true;
    package = pkgs.claude-desktop;
    cowork.kvmUsers = [ "frame-automobile" ];
  };

  # For claude-desktop's runtime-downloaded claude-code, not the patchelf'd one
  # modules/workstation installs — hosts/frame-automata/default.nix carries the
  # full why.
  programs.nix-ld.enable = true;

  # Weekly update from whatever is committed, so deploying is pushing.
  # upgrade = false is required, not cosmetic: --upgrade is added whenever
  # `channel` is null, and this host has no channels to refresh. power.nix
  # additionally gates the unit on AC.
  system.autoUpgrade = {
    enable = true;
    flake = "github:FrameAutomata/nix-config#frame-automobile";
    operation = "switch";
    upgrade = false;
    dates = "Mon 02:00";
    persistent = true;
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  # Laptop-only; the shared workstation app set is in modules/workstation.
  environment.systemPackages = with pkgs; [
    keyd # the CLI (`keyd monitor`); services.keyd installs only the daemon
  ];

  system.stateVersion = "26.05"; # never change this
}
