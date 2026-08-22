# Three repurposed Windows drives, wiped 2026-08-22 and re-made as ext4.
{ ... }:

let
  # nofail keeps a failed or removed drive off local-fs.target's critical path,
  # so the desktop still boots to SDDM without it. The short device timeout
  # replaces systemd's 90s default wait for a device that is simply gone.
  local = [
    "nofail"
    "x-systemd.device-timeout=5s"
  ];
in

{
  fileSystems = {
    # addlink 954G NVMe — Steam library
    "/mnt/games" = {
      device = "/dev/disk/by-label/games";
      fsType = "ext4";
      options = local;
    };

    # Seagate 3.6T — bulk storage
    "/mnt/data" = {
      device = "/dev/disk/by-label/data";
      fsType = "ext4";
      options = local;
    };

    # WD 932G — scratch
    "/mnt/scratch" = {
      device = "/dev/disk/by-label/scratch";
      fsType = "ext4";
      options = local;
    };
  };

  # A fresh ext4 mounts root-owned, which would leave the desktop user unable to
  # write. systemd-tmpfiles-setup runs after local-fs.target, so these land on
  # the mounted filesystem rather than the empty mountpoint underneath it.
  systemd.tmpfiles.rules = [
    "d /mnt/games   0755 frame-automata users -"
    "d /mnt/data    0755 frame-automata users -"
    "d /mnt/scratch 0755 frame-automata users -"
  ];
}
