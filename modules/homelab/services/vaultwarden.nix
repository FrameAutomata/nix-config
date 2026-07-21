{ config, lib, ... }:
let
  cfg = config.homelab.services.vaultwarden;
  homelab = config.homelab;
  mkSecretOption = import ../secret-option.nix { inherit lib config; };
  subdomain = "vault";
in
{
  options.homelab.services.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";
    allowSignups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow open account registration (hosts flip this on during household onboarding)";
    };
    adminTokenFile = mkSecretOption {
      secret = "vaultwarden-admin";
      optionPath = "homelab.services.vaultwarden";
      hint = "an EnvironmentFile with ADMIN_TOKEN=..., which unlocks the /admin page";
      description = "EnvironmentFile containing ADMIN_TOKEN=...";
    };
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      environmentFile = cfg.adminTokenFile;
      # upstream derives DOMAIN (with the https:// scheme) from this
      domain = "${subdomain}.${homelab.baseDomain}";
      # not restated defaults: upstream's ::1/8222 live in the option-level
      # default, which is discarded entirely once `config` is set
      config = {
        SIGNUPS_ALLOWED = cfg.allowSignups;
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = 8222;
      };
    };

    homelab.services.backup = {
      statePaths = [ "/var/lib/vaultwarden" ];
      quiesceUnits = [ "vaultwarden" ];
    };

    homelab.nginx.internal.${subdomain} = {
      proxyPass = "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
      # live vault sync pushes over /notifications/hub
      websockets = true;
      dashboard = {
        name = "Vaultwarden";
        description = "Password manager";
        icon = "vaultwarden.svg";
        category = "Household";
      };
    };
  };
}
