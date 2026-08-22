# Three repurposed Windows drives, wiped 2026-08-22 and re-made as ext4.
{ ... }:

let
  # nofail keeps a failed or removed drive off local-fs.target's critical path,
  # so the desktop still boots to SDDM without it. The device timeout replaces
  # systemd's 90s default wait for a device that is simply gone.
  #
  # 30s, not 5s: after switch-root the udev database is wiped and every device
  # is re-probed from scratch, so the by-label symlinks these mounts wait on are
  # not the ones initrd made. On this box that re-probe lands them ~7.6s after
  # the mount jobs start (blkid on a spun-up 4TB disk, queued behind the USB
  # tree), which quietly blew the old 5s deadline by ~1.6s: the device units
  # timed out, fsck failed on the dependency, and nofail turned all three
  # missing drives into a silent boot. Root escapes this only because
  # x-initrd.mount mounts it before the wipe. Keep the headroom well above the
  # observed ~8s; a genuinely absent drive still costs 30s, not 90s.
  local = [
    "nofail"
    "x-systemd.device-timeout=30s"
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
  # write. Each drive's root inode was chowned once at setup, and that ownership
  # lives on the filesystem itself — it is what actually makes these writable.
  #
  # These rules do not maintain it, despite appearances. systemd-tmpfiles-setup
  # is ordered after local-fs.target, but nofail (above) drops the mounts'
  # ordering into that target, so local-fs.target is reached without them and
  # tmpfiles runs several seconds before the drives mount — they are still
  # waiting on the post-switch-root udev re-probe that tmpfiles does not wait
  # for. So these land on the bare mountpoints underneath, which the
  # filesystems then cover. Harmless, and it keeps the mountpoints sane while a
  # drive is missing, but a newly made filesystem still needs a manual chown:
  # this will not do it for you.
  systemd.tmpfiles.rules = [
    "d /mnt/games   0755 frame-automata users -"
    "d /mnt/data    0755 frame-automata users -"
    "d /mnt/scratch 0755 frame-automata users -"
  ];
}
