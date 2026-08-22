# agenix rules for the desktop's own secrets. Separate from the server's set on
# purpose: each host decrypts only what it needs, and keeping them in different
# directories means enrolling this host required no rekey of the server's five.
#
# The host key decrypts at activation; the admin key edits. Run the CLI from
# this directory — it resolves rules relative to cwd:
#   cd hosts/frame-automata/secrets && agenix -e samba-client.age
let
  keys = import ../../../keys.nix;
in
{
  # mount.cifs credentials for the homelab Samba shares — exactly two lines,
  # `username=` and `password=`, matching what smbpasswd was set to on the
  # server. Consumed by homelabClient.mounts.credentialsFile.
  "samba-client.age".publicKeys = [
    keys.admin
    keys.hosts.frame-automata
  ];
}
