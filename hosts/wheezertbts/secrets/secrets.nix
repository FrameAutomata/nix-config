# agenix rules: which keys can decrypt each secret.
# The host key decrypts at activation; the admin key edits via `agenix -e`.
let
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPp3lCoxw+RdLFkALHGG+zmHw1NkMMaV8bQ7Km2yIX7 corbi@DESKTOP-CJ3RO7R";
  host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPnqO0V6XOC1WpxHWz38NjB2h7zBKShsVfRRSZDiqB1z root@nixos";
  all = [ admin host ];
in
{
  "duckdns-token.age".publicKeys = all;
}
