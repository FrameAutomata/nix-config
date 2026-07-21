# qBittorrent, confined to the WireGuard netns (wireguard-netns.nix): all
# torrent traffic goes through the tunnel or nowhere. The WebUI is reachable
# on the host via a systemd socket proxy (the only deliberate hole), fronted
# by the internal vhost. Socket-proxy pattern adapted from notthebee (MIT).
{ pkgs, config, lib, ... }:
let
  homelab = config.homelab;
  cfg = homelab.services.qbittorrent;
  ns = homelab.services.wireguard-netns.namespace;
  # inside the netns qBittorrent keeps its default 8080 (nothing else lives
  # there); on the host that port belongs to Headscale, so the proxy listens
  # on proxyPort instead
  webuiPort = 8080;
in
{
  options.homelab.services.qbittorrent = {
    enable = lib.mkEnableOption "qBittorrent inside the VPN network namespace";
    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Host-side port the socket proxy exposes the WebUI on (nginx upstream)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = homelab.services.wireguard-netns.enable;
        message = "homelab.services.qbittorrent requires homelab.services.wireguard-netns (no VPN, no torrents)";
      }
    ];

    services.qbittorrent = {
      enable = true;
      inherit webuiPort;
      group = homelab.group;
      # NOT serverConfig: the module rewrites qBittorrent.conf on every start
      # when it's set, clobbering UI-made settings (like the admin password)
      extraArgs = [ "--confirm-legal-notice" ];
    };

    systemd.services.qbittorrent = {
      bindsTo = [ "netns@${ns}.service" ];
      requires = [ "${ns}.service" ];
      after = [ "${ns}.service" ];
      serviceConfig = {
        NetworkNamespacePath = "/var/run/netns/${ns}";
        # the netns must resolve via the VPN's DNS, not the host's resolv.conf
        BindReadOnlyPaths = [ "/etc/netns/${ns}/resolv.conf:/etc/resolv.conf" ];
        # downloads land group-writable for the arrs (shared `media` group)
        UMask = "0002";
      };
    };

    systemd.sockets.qbittorrent-proxy = {
      enable = true;
      description = "Host-side socket for the qBittorrent WebUI proxy";
      listenStreams = [ "127.0.0.1:${toString cfg.proxyPort}" ];
      wantedBy = [ "sockets.target" ];
    };

    systemd.services.qbittorrent-proxy = {
      description = "Proxy to the qBittorrent WebUI inside the ${ns} namespace";
      requires = [ "qbittorrent.service" "qbittorrent-proxy.socket" ];
      after = [ "qbittorrent.service" "qbittorrent-proxy.socket" ];
      unitConfig.JoinsNamespaceOf = "qbittorrent.service";
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=5min 127.0.0.1:${toString webuiPort}";
        PrivateNetwork = "yes";
      };
    };

    homelab.nginx.internal.qbt = {
      proxyPass = "http://127.0.0.1:${toString cfg.proxyPort}";
    };
  };
}
