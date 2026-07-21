{ config, ... }:

{
  # 2x 12 TB btrfs RAID1 (data + metadata + system all raid1, verified 2026-07-20)
  fileSystems.${config.homelab.mounts.media} = {
    device = "/dev/disk/by-label/media";
    fsType = "btrfs";
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ config.homelab.mounts.media ];
  };

  # unit name = "btrfs-scrub-" + systemd path escape of the mount point
  homelab.services.ntfy.notifyOnFailure = [ "btrfs-scrub-mnt-media" ];
}
