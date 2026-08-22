# Samba shares from the homelab, mounted on demand.
{ config, lib, ... }:

let
  cfg = config.homelabClient.mounts;
  client = config.homelabClient;
in
{
  options.homelabClient.mounts = {
    enable = lib.mkEnableOption "mounting the homelab's Samba shares";

    shares = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "media"
        "shared"
      ];
      description = ''
        Share names as declared in homelab.services.samba.shares. Each mounts
        at <base>/<name>. A member's private area is a share named after their
        handle; the admin's is named after homelab.user. Not derivable from the
        server's config — that is a separate nixosSystem eval.
      '';
    };

    base = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/homelab";
      description = "Directory the shares mount under.";
    };

    owner = lib.mkOption {
      type = lib.types.str;
      description = "Local user that owns the mounted files (CIFS has no uid mapping of its own).";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        Root-only file holding the Samba login, in mount.cifs credentials
        format: `username=`, `password=`, one per line. A string rather than a
        path — a path literal would be copied into the world-readable store.
      '';
    };
  };

  # imports escapes the enclosing mkIf, so this guards on both.
  config = lib.mkIf (client.enable && cfg.enable) {
    # cifs-utils arrives automatically: fileSystems' fsType feeds
    # boot.supportedFilesystems, which pulls the mount helper into fsPackages.
    fileSystems = lib.listToAttrs (
      map (
        share:
        lib.nameValuePair "${cfg.base}/${share}" {
          device = "//${client.serverLanIP}/${share}";
          fsType = "cifs";
          options = [
            "credentials=${cfg.credentialsFile}"
            "uid=${cfg.owner}"
            "gid=users"
            "file_mode=0664"
            "dir_mode=0775"
            "iocharset=utf8"
            "vers=3.0"
            # _netdev keeps these off local-fs.target and automount defers the
            # mount to first access, so booting with the server down waits on
            # nothing. nofail makes the automount Wants= rather than Requires=
            # of remote-fs.target, so a share that cannot mount degrades quietly.
            # No noauto (systemd ignores it beside automount) and no
            # device-timeout (ignored for a CIFS URL).
            "nofail"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "x-systemd.mount-timeout=10s"
          ];
        }
      ) cfg.shares
    );
  };
}
