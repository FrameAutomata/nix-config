# Dashboard tiles ride along on each service's homelab.nginx.internal
# registration (its optional `dashboard` field); this module renders every
# vhost that carries one, grouped by category in the canonical order
# (homelab.nginx.dashboardCategories).
{ config, lib, ... }:
let
  cfg = config.homelab.services.homepage;
  homelab = config.homelab;
  subdomain = "home";
in
{
  options.homelab.services.homepage.enable = lib.mkEnableOption "Homepage dashboard";

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      allowedHosts = "${subdomain}.${homelab.baseDomain}";
      settings = {
        title = "wheezertbts";
        hideVersion = true;
      };
      services =
        let
          tiles = lib.attrsToList (
            lib.filterAttrs (_: vh: vh.dashboard != null) homelab.nginx.internal
          );
          grouped = lib.groupBy (t: t.value.dashboard.category) tiles;
        in
        map (cat: {
          ${cat} = map (t: {
            ${t.value.dashboard.name} = {
              inherit (t.value.dashboard) description icon;
              href = "https://${t.name}.${homelab.baseDomain}";
            };
          }) (lib.sortOn (t: t.value.dashboard.name) grouped.${cat});
        }) (lib.filter (cat: grouped ? ${cat}) homelab.nginx.dashboardCategories);
    };

    # The upstream module has no bind option and the Next.js server binds
    # 0.0.0.0 — reachable in the clear via the trusted tailscale0 interface,
    # skipping the nginx TLS/allowlist layer. server.js reads HOSTNAME, so
    # pin it to loopback like every other internal upstream.
    systemd.services.homepage-dashboard.environment.HOSTNAME = "127.0.0.1";

    homelab.nginx.internal.${subdomain}.proxyPass =
      "http://127.0.0.1:${toString config.services.homepage-dashboard.listenPort}";
  };
}
