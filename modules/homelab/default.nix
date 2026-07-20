{ config, lib, ... }:
let
  cfg = config.homelab;
in
{
  imports = [ ./services ];

  options.homelab = {
    baseDomain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain; service vhosts hang off it as <name>.<baseDomain>";
    };
    lanCIDR = lib.mkOption {
      type = lib.types.str;
      description = "LAN subnet, for internal-vhost allowlists (wired up in Phase 3; not yet consumed)";
    };
    tailnetCIDR = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10";
      description = "Tailnet subnet, for internal-vhost allowlists (wired up in Phase 3; not yet consumed)";
    };
    mounts.media = lib.mkOption {
      # a string, not types.path: the value is used as a mount point / share
      # path, and a path literal here would be copied into the nix store
      type = lib.types.str;
      default = "/mnt/media";
      description = "Bulk media/data mount";
    };
    user = lib.mkOption {
      type = lib.types.str;
      description = "Admin user; set explicitly by the host to keep the coupling visible";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Shared group for media services";
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      description = "Host time zone";
    };
  };

  config = {
    time.timeZone = cfg.timeZone;
    users.groups.${cfg.group}.members = [ cfg.user ];
  };
}
