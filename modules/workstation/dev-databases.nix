# PostgreSQL + ClickHouse for Traceway backend work. That project's
# `transactional_pg telemetry_ch` build is the one deployment shape its own
# tooling cannot exercise on these hosts: docker-compose*.yml and
# scripts/test-backend-pgch.sh both want a container runtime, and neither
# workstation has docker or podman. Running the two databases as ordinary NixOS
# services costs less than adding one.
#
# Imported by frame-automata and frame-automobile rather than by
# modules/workstation/default.nix, which every workstation takes: this is
# Thomas's dev workload, and wonudesktop should never carry a database its user
# has no idea is there. Both machines run the same Traceway checkout, so both
# want it — but each keeps its own databases, migrated and filled separately.
#
# NEITHER UNIT STARTS AT BOOT. A work session runs
#
#   sudo systemctl start postgresql clickhouse
#
# and stops them after; the machine carries nothing the rest of the time. That
# is the whole reason `wantedBy` is cleared below — the services are declared
# so they are reproducible, not so they are always there.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17; # Traceway's CI service container is postgres:17
    enableTCPIP = true; # the backend dials 127.0.0.1:5432, not the socket

    settings.listen_addresses = lib.mkForce "127.0.0.1";

    # Trust on loopback: the backend always sends POSTGRES_PASSWORD and this
    # accepts whatever it is, so a checkout needs no local secret. Safe only in
    # combination with listen_addresses above — it is what keeps the database
    # off every network this laptop roams onto.
    authentication = lib.mkForce ''
      local all all              trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';

    ensureDatabases = [
      "traceway"
      "traceway_test"
    ];

    ensureUsers = [
      {
        name = "traceway";
        # Superuser because the migration runner creates, alters and indexes
        # freely in both databases, while ensureDBOwnership can only hand over
        # the one database whose name matches the role.
        ensureClauses = {
          superuser = true;
          login = true;
          createdb = true;
        };
      }
    ];
  };

  services.clickhouse = {
    enable = true;
    # The LTS line, as CI's 24.8-alpine is. Both nixpkgs ClickHouse packages are
    # 26.x on this release, so local runs are several versions ahead of CI
    # either way: a migration that fails here and passes there is a ClickHouse
    # version difference before it is anything else.
    package = pkgs.clickhouse-lts;

    serverConfig = {
      # A dev-scale ceiling, deliberately not a fraction of the host: ClickHouse
      # otherwise sizes itself against the whole machine (~90% of RAM), which is
      # the wrong share on a workstation whose actual job is the editor and
      # browser around it — and it is the laptop, the smaller of the two, that
      # sets what has to fit. mkDefault so a host with room to spare can raise
      # it without touching this file.
      max_server_memory_usage = lib.mkDefault (4 * 1024 * 1024 * 1024);
      mark_cache_size = lib.mkDefault (512 * 1024 * 1024);
    };
  };

  # The ClickHouse module has no ensureDatabases counterpart, and the backend
  # expects CLICKHOUSE_DATABASE to exist before its migrations run. Type=notify
  # means the server is accepting connections by the time this fires.
  systemd.services.clickhouse.postStart = ''
    for db in traceway traceway_test; do
      ${config.services.clickhouse.package}/bin/clickhouse-client \
        --host 127.0.0.1 --query "CREATE DATABASE IF NOT EXISTS $db"
    done
  '';

  systemd.services.postgresql.wantedBy = lib.mkForce [ ];
  systemd.services.clickhouse.wantedBy = lib.mkForce [ ];
}
