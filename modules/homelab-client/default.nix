# Client-side hookups to the wheezertbts homelab, for machines that USE it
# rather than run it. Never imports modules/homelab (the server side).
{ config, lib, pkgs, ... }:

let
  cfg = config.homelabClient;
  site = import ../../site.nix;
  notify = import ../notify.nix {
    inherit config pkgs lib;
    inherit (cfg) notifyOnFailure;
    hostName = config.networking.hostName;
    endpoint = "https://${site.ntfySubdomain}.${cfg.baseDomain}/${cfg.ntfyTopic}";
  };
in
{
  imports = [ ./mounts.nix ];

  options.homelabClient = {
    enable = lib.mkEnableOption "client-side hookups to the wheezertbts homelab";

    baseDomain = lib.mkOption {
      type = lib.types.str;
      default = site.baseDomain;
      description = "The homelab's base domain; service vhosts hang off it.";
    };

    serverLanIP = lib.mkOption {
      type = lib.types.str;
      default = site.lanIP;
      description = "The server's static LAN IP. Mounts use it so they never depend on DNS.";
    };

    ntfyTopic = lib.mkOption {
      type = lib.types.str;
      default = site.ntfyTopic;
      description = "ntfy topic that failure alerts publish to.";
    };

    notifyOnFailure = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nixos-upgrade" ];
      description = "Units (no .service suffix) that push an ntfy alert when they fail.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      # Inbound UDP 41641: lets peers connect directly instead of via a DERP relay.
      openFirewall = true;
      # "client" only loosens rp_filter, which accepting a subnet route
      # requires. "server"/"both" would additionally enable IP forwarding.
      useRoutingFeatures = "client";
      # AdGuard's split DNS answers *.<baseDomain> with the LAN IP, so reaching
      # those from outside the house needs the server's advertised route.
      extraSetFlags = [ "--accept-routes" ];
      # No authKeyFile: keys expire in 24h, so login is a one-time manual
      # `tailscale up` and persists in /var/lib/tailscale.
    };

    inherit (notify) assertions;
    inherit (notify) systemd;
  };
}
