# Prowlarr's NixOS module has no user/group options (it runs DynamicUser);
# fine — it only talks to indexers and the other arrs over HTTP, it never
# touches /mnt/media.
{ config, lib, ... }:
let
  cfg = config.homelab.services.prowlarr;
in
{
  options.homelab.services.prowlarr.enable = lib.mkEnableOption "Prowlarr indexer manager";

  config = lib.mkIf cfg.enable {
    services.prowlarr.enable = true;
    homelab.nginx.internal.prowlarr = {
      proxyPass = "http://127.0.0.1:${toString config.services.prowlarr.settings.server.port}";
      dashboard = {
        name = "Prowlarr";
        description = "Indexer manager";
        icon = "prowlarr.svg";
        category = "Downloads";
      };
    };
  };
}
