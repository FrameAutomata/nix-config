{
  description = "NixOS homelab — wheezertbts";

  inputs = {
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
