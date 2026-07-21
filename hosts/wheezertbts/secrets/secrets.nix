# agenix rules: which keys can decrypt each secret.
# The host key decrypts at activation; the admin key edits via `agenix -e`.
# If the host key ever rotates (OS reinstall), secrets must be rekeyed from
# the desktop (the admin key is the recovery path): agenix -r from this dir.
let
  keys = import ../keys.nix;
  all = [ keys.admin keys.host ];
in
{
  "duckdns-token.age".publicKeys = all;
  # Surfshark WireGuard config in `wg setconf` format (see wireguard-netns.nix)
  "surfshark-wg.age".publicKeys = all;
}
