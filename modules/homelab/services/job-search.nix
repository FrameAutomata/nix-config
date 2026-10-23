# job-search-pipeline triage UI — one instance per household member.
#
# Each person's job search is a SEPARATE checkout with its own career-ops data,
# its own cloud repo and its own password; the app has no multi-user model and
# the checkout is the isolation boundary. So this runs N independent services
# rather than one, and nothing is shared between them but the nginx layer.
#
# The pipeline itself still runs in GitHub Actions. This hosts only the triage
# board, which is what a person needs to see their queue and move a card —
# measured at ~600 min/month of Actions for two copies against a 2,000 free
# tier, so there is no minutes argument for moving the scraping here, and doing
# so would mean jobspy's numpy==1.26.3 pin and scraping from a residential IP.
#
# WHY UI_LAN IS SET even though this is behind a proxy: without it the server
# is loopback-only and REFUSES the cross-origin POST a browser at
# https://<name>.<baseDomain> sends. UI_LAN is what accepts that Origin — and
# it also makes UI_PASSWORD mandatory, which is the point.
#
# THE LOAD-BEARING FLAG IS `--forwarded-allow-ips`. nginx is the TCP peer, so
# without X-Forwarded-For being honoured every request looks like loopback, and
# server.py's loopback-only routes — start-over (wipes job-search state), local
# pipeline runs, Add-Job — open to anyone who can reach the vhost. Verified
# both ways: with the header POST /api/reset is refused 403; without it the
# route RUNS. nginx sends it via `recommendedProxySettings = true`; this flag is
# the other half, stated explicitly because nothing fails loudly if it regresses.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homelab.services.jobSearch;
  homelab = config.homelab;

  # The UI imports NONE of the scraping stack (no jobspy/pandas/numpy/yake), so
  # it needs no python312 pin and no wheel-loader workaround — every dependency
  # is in nixpkgs. This list mirrors `packages.<system>.ui` in the app repo's
  # own flake.nix; the drift-free alternative is adding that repo as a flake
  # input and using `inputs.job-search-pipeline.packages.${pkgs.system}.ui`,
  # which is worth doing if this list ever grows.
  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      markdown
      python-multipart
      pyyaml
      httptools
      uvloop
      websockets
      watchfiles
      python-dotenv
    ]
  );
in
{
  options.homelab.services.jobSearch = {
    enable = lib.mkEnableOption "job-search-pipeline triage UI";

    instances = lib.mkOption {
      default = { };
      description = ''
        One attribute per person. The attribute name is the vhost name and the
        systemd unit suffix, so `cory` serves at cory.<baseDomain>.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              checkout = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Working copy of that person's job-search repo. NOT managed by
                  Nix: it is a git checkout whose career-ops/ data the UI writes
                  on every status change, Refresh and Push, and which the
                  in-app Update button runs `git` against. Clone it once by
                  hand and let the service own it thereafter.
                '';
                example = "/var/lib/job-search/cory";
              };
              port = lib.mkOption {
                type = lib.types.port;
                description = "Loopback port for this instance's uvicorn.";
              };
              environmentFile = lib.mkOption {
                type = lib.types.path;
                description = ''
                  agenix runtime path holding this instance's secrets as
                  KEY=value lines: UI_PASSWORD (required — the server refuses to
                  start under UI_LAN without one) and GH_TOKEN (the Refresh and
                  Push routes shell out to `gh` against that person's PRIVATE
                  repo, and a headless service has no `gh auth login`).
                  Per instance, never shared: the password is the only thing
                  between a tailnet peer and someone else's job search.
                '';
              };
              refreshInterval = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = "*-*-* 13:30:00 UTC";
                description = ''
                  systemd calendar spec for pulling the newest cloud artifact
                  into the local tracker, or null to disable.

                  Default is shortly after the noon-UTC daily. This exists so
                  the board is never stale for someone who only ever moves
                  cards: the Refresh route IS reachable from the tailnet, but a
                  person should not have to know to press it to see today's
                  roles. It runs against loopback, so it is allowed regardless.
                '';
              };
              dashboard = lib.mkOption {
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      name = lib.mkOption { type = lib.types.str; };
                      description = lib.mkOption { type = lib.types.str; };
                    };
                  }
                );
                default = null;
                description = "Homepage tile, or null to leave it off the dashboard.";
              };
              user = lib.mkOption {
                type = lib.types.str;
                default = "jobsearch-${name}";
                description = ''
                  Dedicated system user. One per instance, because the checkout
                  is the isolation boundary — a shared user would put one
                  person's tracker, reports and GH token inside the other's
                  blast radius.
                '';
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    users.users = lib.mapAttrs' (
      name: inst:
      lib.nameValuePair inst.user {
        isSystemUser = true;
        group = inst.user;
        home = inst.checkout;
        description = "job-search triage UI (${name})";
      }
    ) cfg.instances;

    users.groups = lib.mapAttrs' (_: inst: lib.nameValuePair inst.user { }) cfg.instances;

    systemd.services = lib.mkMerge [
      # The UI itself, one per person.
      (lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "job-search-ui-${name}" {
          description = "job-search-pipeline triage UI (${name})";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.gh
            pkgs.git
          ];
          environment = {
            # Accepts the browser's cross-origin POST from the vhost, and makes
            # UI_PASSWORD mandatory. See the header comment.
            UI_LAN = "1";
            # The Host/Origin the browser actually sends. Without this the
            # server works out this machine's own names at startup, which will
            # not include the vhost, and every mutating request is refused.
            UI_ALLOWED_HOSTS = "${name}.${homelab.baseDomain}";
            PYTHONUNBUFFERED = "1";
          };
          serviceConfig = {
            User = inst.user;
            Group = inst.user;
            WorkingDirectory = inst.checkout;
            EnvironmentFile = inst.environmentFile;
            ExecStart = lib.concatStringsSep " " [
              "${pythonEnv}/bin/python -m uvicorn pipeline.app.server:app"
              "--host 127.0.0.1"
              "--port ${toString inst.port}"
              # THE load-bearing flag — see the header comment.
              "--forwarded-allow-ips 127.0.0.1"
            ];
            Restart = "on-failure";
            RestartSec = 5;
            # The checkout is mutable state this service owns; everything else
            # is off limits. Not ProtectHome: the checkout may live under one.
            ReadWritePaths = [ inst.checkout ];
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
          };
        }
      ) cfg.instances)

      # Server-side Refresh, so a person who only moves cards still sees
      # today's roles rather than having to know to press a button. curl
      # against loopback, which the peer rule allows unconditionally; the
      # password is still required, so it comes from the same secret file.
      # A 502 is offline/no-gh, and that route leaves local state untouched by
      # design, so a failed poll is not worth alerting on.
      (lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "job-search-refresh-${name}" (
          lib.mkIf (inst.refreshInterval != null) {
            description = "Pull the newest cloud tracker into ${name}'s board";
            after = [ "job-search-ui-${name}.service" ];
            serviceConfig = {
              Type = "oneshot";
              User = inst.user;
              EnvironmentFile = inst.environmentFile;
              ExecStart = pkgs.writeShellScript "job-search-refresh-${name}" ''
                exec ${pkgs.curl}/bin/curl -fsS -m 300 -X POST \
                  -u ":$UI_PASSWORD" \
                  -H 'Host: ${name}.${homelab.baseDomain}' \
                  -H 'Origin: https://${name}.${homelab.baseDomain}' \
                  http://127.0.0.1:${toString inst.port}/api/refresh
              '';
            };
          }
        )
      ) cfg.instances)
    ];

    systemd.timers = lib.mapAttrs' (
      name: inst:
      lib.nameValuePair "job-search-refresh-${name}" (
        lib.mkIf (inst.refreshInterval != null) {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = inst.refreshInterval;
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
        }
      )
    ) cfg.instances;

    homelab.nginx.internal = lib.mapAttrs (
      name: inst:
      {
        proxyPass = "http://127.0.0.1:${toString inst.port}";
      }
      // lib.optionalAttrs (inst.dashboard != null) {
        dashboard = {
          inherit (inst.dashboard) name description;
          icon = "briefcase.svg";
          category = "Household";
        };
      }
    ) cfg.instances;

    # career-ops holds every evaluation report and the tracker — the only copy
    # of months of work outside the Actions cache, which evicts after 7 days.
    homelab.services.backup = {
      statePaths = lib.mapAttrsToList (_: inst: inst.checkout) cfg.instances;
      quiesceUnits = lib.mapAttrsToList (name: _: "job-search-ui-${name}") cfg.instances;
    };
  };
}
