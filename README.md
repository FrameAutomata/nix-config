# nix-config

NixOS flake for the `wheezertbts` household homelab server.

**Status:** Phase 0 — the pre-existing single-file configuration wrapped in a
flake verbatim, no behavior change. Module structure comes in later phases.

## Rebuild

```sh
sudo nixos-rebuild build --flake .    # dry build
sudo nixos-rebuild test --flake .     # apply without making it the boot default
sudo nixos-rebuild switch --flake .
sudo nixos-rebuild switch --rollback  # undo
```

## Planned structure

- `hosts/<name>/` — per-machine config + agenix secrets
- `modules/common/` — host-agnostic base (locale, nix settings, ssh, nvidia)
- `modules/homelab/` — `homelab.*` options and service modules

## Credits

Module patterns (wireguard-netns, socket-proxy, the `homelab.services.*`
option layout) are adapted from
[notthebee's nix-config](https://git.notthebe.ee/notthebee/nix-config) (MIT).
