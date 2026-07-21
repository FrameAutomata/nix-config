# WireGuard client network namespace — kill switch by construction: wg0 is
# created on the host, moved into the netns, and becomes the ONLY default
# route in there. If the tunnel is down, nothing in the netns can reach the
# internet at all. Services opt in via NetworkNamespacePath.
# Adapted from notthebee's nix-config (MIT).
{ pkgs, config, lib, ... }:
let
  cfg = config.homelab.services.wireguard-netns;
in
{
  options.homelab.services.wireguard-netns = {
    enable = lib.mkEnableOption "WireGuard client network namespace";
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "wg_client";
      description = "Name of the network namespace to create";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a `wg setconf` format file (NOT wg-quick): [Interface]
        PrivateKey plus [Peer] PublicKey/Endpoint/AllowedIPs. Address and
        DNS lines are not valid here — they map to privateIP and dnsIPs.
      '';
    };
    privateIP = lib.mkOption {
      type = lib.types.str;
      description = "Tunnel address with prefix (the Address from the provider's config, e.g. 10.14.0.2/16)";
    };
    dnsIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "VPN provider DNS servers, used as the netns resolv.conf (leaking DNS to LAN resolvers would bypass the tunnel)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services."netns@" = {
      description = "%I network namespace";
      before = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.iproute2}/bin/ip netns add %I";
        ExecStop = "${pkgs.iproute2}/bin/ip netns del %I";
      };
    };

    environment.etc."netns/${cfg.namespace}/resolv.conf".text =
      lib.concatMapStrings (ip: "nameserver ${ip}\n") cfg.dnsIPs;

    systemd.services.${cfg.namespace} = {
      description = "WireGuard tunnel inside the ${cfg.namespace} namespace";
      bindsTo = [ "netns@${cfg.namespace}.service" ];
      requires = [ "network-online.target" ];
      after = [
        "netns@${cfg.namespace}.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writers.writeBash "wg-up" ''
          set -e
          ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
          ${pkgs.iproute2}/bin/ip link set wg0 netns ${cfg.namespace}
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} address add ${cfg.privateIP} dev wg0
          ${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace} \
            ${pkgs.wireguard-tools}/bin/wg setconf wg0 ${cfg.configFile}
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set wg0 up
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link set lo up
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route add default dev wg0
        '';
        ExecStop = pkgs.writers.writeBash "wg-down" ''
          set -e
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} route del default dev wg0
          ${pkgs.iproute2}/bin/ip -n ${cfg.namespace} link del wg0
        '';
      };
    };
  };
}
