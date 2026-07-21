# Jellyseerr — media request front-end for the household. The upstream
# NixOS option set was renamed services.jellyseerr -> services.seerr in
# this nixpkgs; the homelab-facing name stays jellyseerr.
{ config, lib, ... }:
let
  cfg = config.homelab.services.jellyseerr;
in
{
  options.homelab.services.jellyseerr.enable = lib.mkEnableOption "Jellyseerr request manager";

  config = lib.mkIf cfg.enable {
    services.seerr.enable = true;
    homelab.nginx.internal.requests = {
      proxyPass = "http://127.0.0.1:${toString config.services.seerr.port}";
      dashboard = {
        name = "Jellyseerr";
        description = "Request movies & shows";
        icon = "jellyseerr.svg";
        category = "Media";
      };
    };
  };
}
