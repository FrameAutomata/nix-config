# agenix rules: which keys can decrypt each secret.
# The host key decrypts at activation; the admin key edits via `agenix -e`.
# If the host key ever rotates (OS reinstall), secrets must be rekeyed from
# the desktop (the admin key is the recovery path): agenix -r from this dir.
let
  keys = import ../../../keys.nix;
  # Same two keys this file has always named, so nothing here needs rekeying:
  # the desktop's host key is enrolled in keys.nix but deliberately not added
  # to these — it has no business decrypting restic or B2 credentials.
  all = [ keys.admin keys.hosts.wheezertbts ];
in
{
  "duckdns-token.age".publicKeys = all;
  # Surfshark WireGuard config in `wg setconf` format (see wireguard-netns.nix)
  "surfshark-wg.age".publicKeys = all;
  # EnvironmentFile with ADMIN_TOKEN=... for Vaultwarden's /admin page
  "vaultwarden-admin.age".publicKeys = all;
  # restic repo password (shared by the local and B2 repos)
  "restic-password.age".publicKeys = all;
  # EnvironmentFile with AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY for the B2
  # application key (restic talks to B2 over its S3-compatible API)
  "b2-env.age".publicKeys = all;
}
