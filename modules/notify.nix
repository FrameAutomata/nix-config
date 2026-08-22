# ntfy failure alerts, shared by the server (posts to localhost) and its
# clients (post to the public vhost). A plain function file — the
# modules/homelab/secret-option.nix idiom — so neither tree imports the other.
#
# Returns a systemd.services attrset: the homelab-notify@ template plus an
# onFailure hook on each named unit.
{
  pkgs,
  lib,
  hostName,
  endpoint,
  notifyOnFailure,
}:

let
  # Journal tail rides stdin, not argv — argv is world-readable in /proc.
  script = pkgs.writeShellScript "homelab-notify" ''
    unit="$1"
    ${pkgs.systemd}/bin/journalctl -u "$unit" -n 15 --no-pager -o cat \
      | ${pkgs.coreutils}/bin/tail -c 3800 \
      | ${pkgs.curl}/bin/curl -fsS -m 10 \
          -H "Title: ${hostName}: $unit failed" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          --data-binary @- \
          "${endpoint}"
  '';
in
{
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
})
