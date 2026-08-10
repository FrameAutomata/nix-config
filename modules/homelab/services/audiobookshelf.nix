{ config, lib, ... }:
let
  cfg = config.homelab.services.audiobookshelf;
in
{
  options.homelab.services.audiobookshelf.enable = lib.mkEnableOption "Audiobookshelf";

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      # the direct port stays reachable for LAN app traffic, but via the
      # lanPorts registry instead of upstream's global list
      openFirewall = false;
      host = "0.0.0.0"; # defaults to localhost-only, which blocks every other device
    };
    # derived, so unlike samba/jellyfin this cannot drift on the port number;
    # only the *shape* could (upstream opens exactly this one port today —
    # nixos/modules/services/web-apps/audiobookshelf.nix:89-91, f197f8e)
    homelab.lanPorts.audiobookshelf.tcp = [ config.services.audiobookshelf.port ];
    homelab.nginx.internal.abs = {
      proxyPass = "http://127.0.0.1:${toString config.services.audiobookshelf.port}";
      websockets = true; # the abs web UI is socket.io-based
      dashboard = {
        name = "Audiobookshelf";
        description = "Audiobooks & podcasts";
        icon = "audiobookshelf.svg";
        category = "Media";
      };
    };
    users.groups.${config.homelab.group}.members = [ "audiobookshelf" ];

    homelab.services.backup = {
      statePaths = [ "/var/lib/audiobookshelf" ];
      quiesceUnits = [ "audiobookshelf" ];
    };
  };
}
