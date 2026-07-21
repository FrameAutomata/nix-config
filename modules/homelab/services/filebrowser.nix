{ config, lib, ... }:
let
  cfg = config.homelab.services.filebrowser;
  homelab = config.homelab;
  fb = config.services.filebrowser;
in
{
  options.homelab.services.filebrowser.enable = lib.mkEnableOption "FileBrowser web file manager";

  config = lib.mkIf cfg.enable {
    services.filebrowser = {
      enable = true;
      settings = {
        address = "127.0.0.1";
        # upstream default is 8080, which belongs to Headscale on this host
        port = 8083;
        root = homelab.mounts.media;
      };
    };

    # The daemon serves every household member, so it needs entry into each
    # personal group; its per-account jails (configured in the admin UI —
    # ALWAYS set a member's scope before handing out credentials, the
    # default scope is the whole root) keep members apart at the app layer.
    # No human logs in as this user.
    homelab.household.serviceAccounts = [ fb.user ];
    # ...and the media group, so accounts scoped to the library can write it
    users.groups.${homelab.group}.members = [ fb.user ];

    homelab.services.backup = {
      statePaths = [ "/var/lib/filebrowser" ];
      quiesceUnits = [ "filebrowser" ];
    };

    # The upstream module tmpfiles-manages settings.root — chown+chmod to
    # filebrowser:filebrowser 0700, re-applied on every boot — which on the
    # live media mount would cut off samba and every media service. There is
    # no upstream opt-out, so replace the whole rule set: keep its private
    # state/cache rules, leave the mount itself unmanaged.
    systemd.tmpfiles.settings.filebrowser = lib.mkForce {
      ${fb.settings.cache-dir}.d = {
        inherit (fb) user group;
        mode = "0700";
      };
      ${dirOf fb.settings.database}.d = {
        inherit (fb) user group;
        mode = "0700";
      };
    };

    systemd.services.filebrowser = {
      # supplementary groups are only picked up at exec time; tie the unit
      # text to the member list so adding a roommate restarts the daemon
      restartTriggers = [ (toString homelab.household.members) ];
      serviceConfig = {
        # Upstream UMask 0077 would make everything FileBrowser writes
        # private to its daemon user; household areas need group-shared
        # files (0664/0775, with setgid dirs picking the group).
        UMask = lib.mkForce "0002";
        # ...but the Bolt DB (password hashes, JWT signing secret) then
        # lands group/world-readable, so the state dir must stay owner-only
        # — systemd would otherwise re-apply its 0755 default every start
        StateDirectoryMode = "0700";
      };
    };

    homelab.nginx.internal.files = {
      proxyPass = "http://127.0.0.1:${toString fb.settings.port}";
      dashboard = {
        name = "FileBrowser";
        description = "Web file manager";
        icon = "filebrowser.svg";
        category = "Household";
      };
    };
  };
}
