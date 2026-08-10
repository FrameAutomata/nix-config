{ config, lib, ... }:
let
  cfg = config.homelab.services.samba;
  homelab = config.homelab;
in
{
  options.homelab.services.samba = {
    enable = lib.mkEnableOption "Samba file sharing";
    shares = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Directory the share exports";
            };
            validUsers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Accounts allowed to authenticate (a list so modules can merge grants)";
            };
            forceGroup = lib.mkOption {
              type = lib.types.str;
              description = "Group ownership forced on files created through the share";
            };
            browseable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            createMask = lib.mkOption {
              type = lib.types.str;
              default = "0664";
            };
            directoryMask = lib.mkOption {
              type = lib.types.str;
              default = "0775";
            };
            vetoFiles = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Names neither visible nor accessible through this share";
            };
          };
        }
      );
      default = { };
      description = "Samba shares, registered by modules (same registration pattern as homelab.nginx.internal)";
    };
  };

  config = lib.mkIf cfg.enable {
    homelab.services.samba.shares.media = {
      path = homelab.mounts.media;
      # admin always; household.nix merges the member handles in
      validUsers = [ homelab.user ];
      forceGroup = homelab.group;
      # the household areas are reached only through their own shares
      # (household.nix) with per-area auth — never through the library share
      vetoFiles = [ "Private" "Shared" ];
    };

    services.samba = {
      enable = true;
      # via the lanPorts registry instead of upstream's global list
      openFirewall = false;
      settings = {
        global."workgroup" = "WORKGROUP";
      }
      // lib.mapAttrs (
        _: share:
        {
          inherit (share) path;
          "valid users" = lib.concatStringsSep " " share.validUsers;
          "public" = "no";
          "writeable" = "yes";
          "browseable" = if share.browseable then "yes" else "no";
          "force group" = share.forceGroup;
          "create mask" = share.createMask;
          "directory mask" = share.directoryMask;
        }
        // lib.optionalAttrs (share.vetoFiles != [ ]) {
          "veto files" = "/${lib.concatStringsSep "/" share.vetoFiles}/";
        }
      ) cfg.shares;
    };

    services.samba-wsdd = {
      enable = true;
      openFirewall = false;
    };

    # Hand copies of the port sets the upstream openFirewall flags would have
    # opened. NOTHING checks these against nixpkgs — there is no way to read
    # what upstream *would* set without enabling the flag — so re-read the
    # sources on a nixpkgs bump (last verified nixos-26.05 f197f8e):
    #   nixos/modules/services/network-filesystems/samba.nix:258-265
    #   nixos/modules/services/network-filesystems/samba-wsdd.nix:143-146
    homelab.lanPorts.samba = {
      tcp = [ 139 445 ]; # SMB
      udp = [ 137 138 ]; # NetBIOS name/datagram
    };
    homelab.lanPorts.samba-wsdd = {
      tcp = [ 5357 ]; # WSD HTTP
      udp = [ 3702 ]; # WS-Discovery multicast
    };

    # smbpasswd database; small tdb files, safe to live-copy
    homelab.services.backup.statePaths = [ "/var/lib/samba" ];
  };
}
