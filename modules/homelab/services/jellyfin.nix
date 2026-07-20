{ config, lib, ... }:
let
  cfg = config.homelab.services.jellyfin;
in
{
  options.homelab.services.jellyfin.enable = lib.mkEnableOption "Jellyfin media server";

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };
    users.groups.${config.homelab.group}.members = [ "jellyfin" ];
  };
}
