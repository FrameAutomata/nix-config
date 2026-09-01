# PLACEHOLDER — this host has not been installed yet.
#
# Replace this file with a scan taken ON the machine, then commit and push it:
#
#   nixos-generate-config --show-hardware-config > hosts/wonudesktop/hardware-configuration.nix
#
# It throws rather than guessing. A hand-written stub would be worse than no
# file at all: the disk UUIDs, the initrd module list and the CPU microcode
# switch are all facts about hardware nobody here has looked at, and a wrong
# one produces a generation that builds fine and then does not boot. `throw`
# fails at eval, which is the loudest, earliest place to fail.
#
# Until it is replaced, `nix flake check` is red for the whole repo and
# `nix eval .#nixosConfigurations.wonudesktop...` fails — that is this file
# talking, not a broken config. The other three hosts are separate
# nixosSystem evals and are unaffected.
{ ... }:

throw ''
  hosts/wonudesktop/hardware-configuration.nix is still the placeholder.

  Boot the NixOS installer on the machine, partition it (UEFI — modules/common
  uses systemd-boot), then:

    nixos-generate-config --root /mnt
    cp /mnt/etc/nixos/hardware-configuration.nix <this repo>/hosts/wonudesktop/

  See the wonudesktop section of README.md for the rest of the install.
''
