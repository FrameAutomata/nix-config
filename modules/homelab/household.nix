# Three-tier privacy model for household members:
#   1. Private/<name>  — per-person, 2770 <name>:<name>; Samba auth AND
#      filesystem permissions each independently deny other members.
#   2. Shared          — communal drop zone, group `household`, 2775.
#   3. The Media library share (samba.nix) — communal by design.
# Honest caveat (also in the README): root on this box can read anything
# except Vaultwarden vaults; admin-proof privacy needs client-side
# encryption (e.g. Cryptomator) on top of a private share.
{ config, lib, pkgs, ... }:
let
  homelab = config.homelab;
  cfg = homelab.household;
  # the admin is always a member; cfg.members holds only the roommates
  allMembers = lib.unique ([ homelab.user ] ++ cfg.members);
  privateRoot = "${homelab.mounts.media}/Private";
  sharedDir = "${homelab.mounts.media}/Shared";
  # handles become unix user/group names, samba share sections, and
  # tmpfiles paths — a colliding or malformed one silently corrupts those
  # namespaces (e.g. a member named "shared" would replace the drop zone)
  reservedHandles = [ "global" "media" "shared" "household" "homes" "printers" ];
in
{
  options.homelab.household = {
    enable = lib.mkEnableOption "the three-tier household privacy model";
    members = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Roommate handles — the admin (homelab.user) is always a member and
        must not be listed. Handles are public (the repo is public), so
        agreed nicknames, never real names. Each gets: a shell-less Unix
        account, a personal group, Private/<name>, membership in
        `household`, and a private Samba share. Samba passwords are set
        manually: sudo smbpasswd -a <name>.
      '';
    };
    serviceAccounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Daemon users granted membership in `household` and every member's
        personal group — filesystem access only; Samba share auth uses
        explicit member lists, so these never cross that boundary.
        Registered by service modules that serve members' files (e.g.
        filebrowser.nix), which must enforce member separation at their
        own app layer.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = map (m: {
      assertion = !(lib.elem m reservedHandles) && builtins.match "[a-z][a-z0-9_-]*" m != null;
      message = "homelab.household: handle \"${m}\" is reserved or not a valid lowercase unix name";
    }) allMembers;

    users.groups = {
      household.members = allMembers ++ cfg.serviceAccounts;
    }
    // lib.genAttrs allMembers (m: {
      members = [ m ] ++ cfg.serviceAccounts;
    });

    users.users = lib.genAttrs cfg.members (m: {
      isNormalUser = true;
      # no interactive login — these accounts exist for Samba/file
      # ownership only (isNormalUser would otherwise grant bash)
      shell = pkgs.shadow;
      description = "household member";
    });

    systemd.tmpfiles.rules = [
      # 0711: members reach their own dir by name, but can't enumerate
      # or stat into anyone else's
      "d ${privateRoot} 0711 root root -"
      "d ${sharedDir} 2775 root household -"
    ]
    ++ map (m: "d ${privateRoot}/${m} 2770 ${m} ${m} -") allMembers;

    homelab.services.samba.shares = {
      # the library is communal — extend its auth to the members
      media.validUsers = cfg.members;
      shared = {
        path = sharedDir;
        validUsers = allMembers;
        forceGroup = "household";
        directoryMask = "2775";
      };
    }
    // lib.genAttrs allMembers (m: {
      path = "${privateRoot}/${m}";
      # auth layer: only the owner may connect; browseable=no hides it
      validUsers = [ m ];
      browseable = false;
      forceGroup = m;
      createMask = "0660";
      directoryMask = "2770";
    });
  };
}
