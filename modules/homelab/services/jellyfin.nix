{ config, lib, ... }:
let
  cfg = config.homelab.services.jellyfin;
  # jellyfin's fixed web port — the NixOS module exposes no option for it
  webPort = 8096;
in
{
  options.homelab.services.jellyfin.enable = lib.mkEnableOption "Jellyfin media server";

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      # LAN clients often connect by IP:8096, so the direct ports stay
      # reachable — via the lanPorts registry rather than upstream's flag,
      # which uses the global (every-interface) list
      openFirewall = false;
    };
    homelab.lanPorts.jellyfin = {
      # hand copy of upstream's openFirewall set, unchecked against nixpkgs —
      # re-read nixos/modules/services/misc/jellyfin.nix:502-511 on a bump
      # (last verified nixos-26.05 f197f8e). Upstream's own warning applies
      # too: these ports are changeable in Jellyfin's web UI, which would
      # desync them from both this list and the proxyPass below.
      tcp = [ webPort 8920 ];
      # SSDP/DLNA + jellyfin's own client autodiscovery — both LAN-only by
      # nature, and useless to a client that can't reach the web port anyway
      udp = [ 1900 7359 ];
    };
    homelab.nginx.internal.jellyfin = {
      proxyPass = "http://127.0.0.1:${toString webPort}";
      websockets = true;
      dashboard = {
        name = "Jellyfin";
        description = "Movies & TV";
        icon = "jellyfin.svg";
        category = "Media";
      };
    };
    users.groups.${config.homelab.group}.members = [ "jellyfin" ];

    homelab.services.backup = {
      statePaths = [ "/var/lib/jellyfin" ];
      quiesceUnits = [ "jellyfin" ];
      excludePaths = [
        "/var/lib/jellyfin/transcodes"
        "/var/lib/jellyfin/cache"
      ];
    };
  };
}
