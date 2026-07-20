# agenix rules: which keys can decrypt each secret.
# The host key decrypts at activation; the admin key edits via `agenix -e`.
let
  keys = import ../keys.nix;
  all = [ keys.admin keys.host ];
in
{
  "duckdns-token.age".publicKeys = all;
}
