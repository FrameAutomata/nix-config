{
  description = "NixOS homelab — wheezertbts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations = {
      # Attr matches the current networking.hostName; renamed in Phase 1.
      "wheezer-the-band-the-server" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./configuration.nix ];
      };
      # Alias: the transient hostname is "nixos", and nixos-rebuild resolves
      # the flake attr from `hostname` output.
      nixos = self.nixosConfigurations."wheezer-the-band-the-server";
    };
  };
}
