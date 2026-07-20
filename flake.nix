{
  description = "NixOS homelab — wheezertbts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.wheezertbts = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/wheezertbts ];
    };
  };
}
