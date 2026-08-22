# ntfy failure alerts, shared by the server (posts to localhost) and its
# clients (post to the public vhost). A plain function file — the
# modules/homelab/secret-option.nix idiom — so neither tree imports the other.
#
# Returns a config fragment: the homelab-notify@ template, an onFailure hook on
# each named unit, and an assertion that each name is real.
{
  config,
  pkgs,
  lib,
  hostName,
  endpoint,
  notifyOnFailure,
}:

let
  script = pkgs.writeShellScript "homelab-notify" ''
    unit="$1"
    # -I scopes to the failed invocation; without it a one-line failure ships
    # 14 lines of an older run. Journal tail rides stdin, not argv — argv is
    # world-readable in /proc.
    body=$(${pkgs.systemd}/bin/journalctl -u "$unit" -I -n 15 --no-pager -o cat \
      | ${pkgs.coreutils}/bin/tail -c 3800)
    # An empty body makes ntfy answer 400, so curl -f fails and the alert is
    # lost precisely when something is wrong. Send a placeholder instead.
    [ -n "$body" ] || body="(no journal output for $unit)"
    printf '%s' "$body" \
      | ${pkgs.curl}/bin/curl -fsS -m 10 \
          -H "Title: ${hostName}: $unit failed" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          --data-binary @- \
          "${endpoint}"
  '';

  # genAttrs below fabricates a service for any name, so a typo would silently
  # emit a [Service]-less stub while the real unit got no alerting. That stub
  # is exactly "no serviceConfig and no script" — checked against every unit
  # the server registers, none of which look like one.
  isStub =
    u:
    let
      s = config.systemd.services.${u} or null;
    in
    s == null || (s.serviceConfig == { } && s.script == "");
in
{
  assertions = map (unit: {
    assertion = !(isStub unit);
    message = ''
      notifyOnFailure: "${unit}" is not a unit this system defines, so the
      alert hook would attach to an empty stub. Check the spelling.
    '';
  }) notifyOnFailure;

  systemd.services = {
    "homelab-notify@" = {
      description = "Failure notification for %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${script} %i";
      };
    };
  }
  // lib.genAttrs notifyOnFailure (unit: {
    onFailure = [ "homelab-notify@${unit}.service" ];
  });
}
