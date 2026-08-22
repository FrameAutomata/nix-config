{
  description = "NixOS configs — wheezertbts (homelab server), frame-automata (desktop)";

  inputs = {
    # TEMPORARY: flake.lock is pinned to f197f8e0c66a, NOT this branch's tip.
    # Branch head cannot build — tailscale 1.98.9 has a bad vendor hash
    # upstream, and tailscale is in system-path, so it fails the whole closure.
    # f197f8e0c66a is the newest 26.05 rev that has vaultwarden >= 1.37.0
    # (required by Bitwarden clients 2026.7.0+) and still predates that bump,
    # so the pin has a floor as well as a ceiling — don't roll it back either.
    # To unpin: nix build --no-link github:nixos/nixpkgs/nixos-26.05#tailscale
    # If that builds, `nix flake update nixpkgs` and delete this comment.
    # Until then a plain `nix flake update` silently re-breaks the rebuild.
    #
    # 2026-08-21: likely clearable — 26.05 head (02e08985a27c) carries
    # tailscale 1.98.10 and vaultwarden 1.37.1, and Hydra has the tailscale
    # build cached. Verify on the box first.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # The desktop's own nixpkgs. Same branch, separate input so a server-side
    # pin never gates a workstation's kernel or Plasma, and the two can move on
    # their own cadence. Update just it with `nix flake update nixpkgs-desktop`.
    nixpkgs-desktop.url = "github:nixos/nixpkgs/nixos-26.05";

    # Both of these expose `overlays.default` as `final.callPackage ./package.nix`,
    # so they build against OUR nixpkgs and their own nixpkgs input is dead
    # weight — hence `follows` on both. It also means claude-code.cachix.org can
    # never serve these builds (its binaries are keyed to upstream's nixpkgs),
    # which is why no substituter is configured for it. Both packages are a
    # fetchurl + patchelf of a prebuilt binary, so building locally is seconds.
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-desktop = {
      url = "github:nmcbride/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs-desktop"; # desktop-only consumer
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
      inputs.home-manager.follows = "";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-desktop,
      agenix,
      claude-code,
      claude-desktop,
      ...
    }:
    let
      # Applied to both hosts. agenix rides the overlay rather than
      # agenix.packages: the latter is built from the `nixpkgs` input, which
      # would drag the server's pinned closure (a second glibc, a second nix)
      # onto the desktop. The overlay builds it against each host's own pkgs;
      # the agenix version is fixed by the flake input either way.
      shared =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            claude-code.overlays.default
            agenix.overlays.default
            (final: _prev: { headroom = final.callPackage ./pkgs/headroom { }; })
          ];
          environment.systemPackages = [ pkgs.agenix ];
        };
    in
    {
      nixosConfigurations = {
        wheezertbts = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/wheezertbts
            agenix.nixosModules.default
            shared
          ];
        };

        # No agenix.nixosModules.default: this host declares no age.secrets. It
        # is the *editor* of the server's secrets (keys.nix `admin`) — the
        # CLI's job, not the activation module's.
        frame-automata = nixpkgs-desktop.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/frame-automata
            shared
            # The module, not just the overlay: Cowork's micro-VM needs OVMF at
            # FHS paths, virtiofsd, vhost_vsock and kvm group membership, which a
            # package-only install skips. package = is overridden in the host so
            # this pulls no closure from claude-desktop's own nixpkgs.
            claude-desktop.nixosModules.default
            { nixpkgs.overlays = [ claude-desktop.overlays.default ]; }
          ];
        };
      };
    };
}
