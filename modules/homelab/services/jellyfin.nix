{ config, lib, ... }:
let
  cfg = config.homelab.services.jellyfin;
in
{
  options.homelab.services.jellyfin.enable = lib.mkEnableOption "Jellyfin media server";

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      # direct port stays open: LAN clients often connect by IP:8096
      openFirewall = true;
    };
    # 8096 is jellyfin's fixed web port (not configurable via the NixOS module)
    homelab.nginx.internal.jellyfin = {
      proxyPass = "http://127.0.0.1:8096";
      websockets = true;
      dashboard = {
        name = "Jellyfin";
        description = "Movies & TV";
        icon = "jellyfin.svg";
        category = "Media";
      };
    };
    users.groups.${config.homelab.group}.members = [ "jellyfin" ];
  };
}
