{ config, lib, ... }:
let
  cfg = config.homelab.services.audiobookshelf;
in
{
  options.homelab.services.audiobookshelf.enable = lib.mkEnableOption "Audiobookshelf";

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      openFirewall = true;
      host = "0.0.0.0"; # defaults to localhost-only, which blocks every other device
    };
    users.groups.${config.homelab.group}.members = [ "audiobookshelf" ];
  };
}
