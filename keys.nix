# Single source for the estate's public keys. Read by the module system
# (authorized keys) and by each host's standalone secrets.nix, which the agenix
# CLI evaluates OUTSIDE the flake — so this stays a plain attrset reachable by
# relative path, for the same reason site.nix is one.
{
  # Thomas's user key. Lives on frame-automata, edits every secret via
  # `agenix -e`, and is the recovery path if a host key rotates.
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPp3lCoxw+RdLFkALHGG+zmHw1NkMMaV8bQ7Km2yIX7 corbi@DESKTOP-CJ3RO7R";

  # Host keys, each decrypting only its own host's secrets at activation.
  # Deliberately not a single `all` list: widening every secret to every host
  # would let the desktop decrypt the server's restic and B2 credentials.
  hosts = {
    wheezertbts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPnqO0V6XOC1WpxHWz38NjB2h7zBKShsVfRRSZDiqB1z root@nixos";
    frame-automata = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILkZ/ryuJ9ZUlWALUxCyv9QxTp+PJZvh1LLPm+C9xXOh root@frame-automata";
  };
}
