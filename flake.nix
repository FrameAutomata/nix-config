{
  description = "NixOS homelab — wheezertbts";

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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Tracks upstream Claude Code releases (hourly bot) — do NOT set
    # inputs.nixpkgs.follows here: overriding it changes the derivation hash
    # and misses the claude-code.cachix.org prebuilt binaries.
    claude-code.url = "github:sadjow/claude-code-nix";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "";
      inputs.home-manager.follows = "";
    };
  };

  outputs = { self, nixpkgs, agenix, claude-code }: {
    nixosConfigurations.wheezertbts = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/wheezertbts
        agenix.nixosModules.default
        (
          { pkgs, ... }:
          { environment.systemPackages = [ agenix.packages.${pkgs.stdenv.hostPlatform.system}.default ]; }
        )
        # Latest-always Claude Code: the overlay makes pkgs.claude-code
        # (referenced in hosts/wheezertbts/default.nix) resolve to this flake's
        # build; the cachix substituter serves it prebuilt.
        (
          { ... }:
          {
            nixpkgs.overlays = [ claude-code.overlays.default ];
            nix.settings = {
              substituters = [ "https://claude-code.cachix.org" ];
              trusted-public-keys = [ "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk=" ];
            };
          }
        )
      ];
    };
  };
}
