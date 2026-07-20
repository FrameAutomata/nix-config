{ config, lib, ... }:
let
  cfg = config.homelab.services.samba;
  homelab = config.homelab;
in
{
  options.homelab.services.samba.enable = lib.mkEnableOption "Samba file sharing";

  config = lib.mkIf cfg.enable {
    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
        };
        media = {
          path = homelab.mounts.media;
          "valid users" = homelab.user;
          "public" = "no";
          "writeable" = "yes";
          "force group" = homelab.group;
          "create mask" = "0664";
          "directory mask" = "0775";
        };
      };
    };

    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
    };
  };
}
