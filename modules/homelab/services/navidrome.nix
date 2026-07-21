{ config, lib, ... }:
let
  cfg = config.homelab.services.navidrome;
  homelab = config.homelab;
in
{
  options.homelab.services.navidrome.enable = lib.mkEnableOption "Navidrome music server";

  config = lib.mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        MusicFolder = "${homelab.mounts.media}/Music";
        # explicit, not default-restating: web UI reachable only through the
        # internal vhost, even if the upstream default bind ever widens
        Address = "127.0.0.1";
      };
    };

    # read access to the music library
    users.groups.${homelab.group}.members = [ "navidrome" ];

    homelab.services.backup = {
      statePaths = [ "/var/lib/navidrome" ];
      quiesceUnits = [ "navidrome" ];
      excludePaths = [ "/var/lib/navidrome/cache" ];
    };

    # Upstream would create a missing MusicFolder as :700 navidrome:media —
    # dead to every group member. Keep the create-only (:) semantics but
    # with the library's perms, so a fresh mount stays usable by all readers.
    systemd.tmpfiles.settings.navidromeDirs.${config.services.navidrome.settings.MusicFolder}.d =
      lib.mkForce {
        user = ":root";
        group = ":${homelab.group}";
        mode = ":2775";
      };

    homelab.nginx.internal.music = {
      proxyPass = "http://127.0.0.1:${toString config.services.navidrome.settings.Port}";
      dashboard = {
        name = "Navidrome";
        description = "Music streaming (Subsonic apps work too)";
        icon = "navidrome.svg";
        category = "Media";
      };
    };
  };
}
