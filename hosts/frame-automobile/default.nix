{
  config,
  lib,
  pkgs,
  ...
}:

let
  site = import ../../site.nix;

  # Physical block offset of the first extent of /var/lib/swapfile. The kernel
  # needs it to find the hibernation image on resume: `resume=` names the
  # filesystem, this names the file inside it. Measured on 2026-08-27, on the
  # switch that first created the file:
  #
  #   sudo filefrag -v /var/lib/swapfile |
  #     awk '$1=="0:" {print substr($4, 1, length($4) - 2); exit}'
  #
  # ext4 blocks and kernel pages are both 4096 on this host, so the number goes
  # in verbatim. null is a legal value here and simply drops the kernel param
  # -- the right state whenever the file's location is not known.
  #
  # RE-MEASURE if the swapfile is ever recreated. Changing `size` does that, so
  # does restoring / from a backup, and so does deleting the file to reclaim
  # the space. A stale offset corrupts nothing, but it fails in the quietest
  # possible way: resume finds no valid image signature and boots fresh,
  # silently losing the session.
  swapfileResumeOffset = 226111488;
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

  # 16 GiB of swap. There is nowhere else to put it: nvme0n1 is /boot plus one
  # full-disk ext4 root, with no free space to carve a partition from, so it is
  # a file on root. swapDevices is a merging list option, so this adds to the
  # empty one in the generated hardware-configuration.nix instead of clashing
  # with it -- same reasoning as the initrd list above. `size` is MiB, and the
  # mkswap unit only acts on it when the file is absent or a different size: it
  # dd's the 16 GiB once and leaves it alone on every later boot.
  #
  # Deliberately NOT randomEncryption, which was the first cut here. A per-boot
  # key would keep paged-out memory unreadable on a disk that is unencrypted
  # (the same fact that keeps this host out of keys.nix), but it is mutually
  # exclusive with hibernation -- the image would be sealed under a key that is
  # gone by the time you resume. This chassis only offers s2idle, no S3, so
  # suspend drains meaningfully overnight and hibernate is worth more than
  # swap secrecy here. The accepted cost: swap, and a full RAM image, land in
  # plaintext on the disk. Encrypting the disk is the fix that gets both.
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # resumeDevice is the filesystem that HOLDS the swapfile, not the swapfile --
  # boot.initrd.systemd is on here, and it turns this into the `resume=` kernel
  # param; swapfileResumeOffset above locates the file within it. Taken from
  # fileSystems rather than pasted, so a re-run of the hardware scan carries it.
  boot.resumeDevice = config.fileSystems."/".device;
  boot.kernelParams = lib.optional (
    swapfileResumeOffset != null
  ) "resume_offset=${toString swapfileResumeOffset}";

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
