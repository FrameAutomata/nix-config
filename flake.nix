{
  description = "NixOS configs — wheezertbts (homelab server), frame-automata (desktop), frame-automobile (laptop), wonudesktop (second desktop)";

  inputs = {
    # The server's nixpkgs. Was pinned to f197f8e0c66a from 2026-07-25 because
    # tailscale 1.98.9 had a bad vendor hash upstream and tailscale is in
    # system-path, so it failed the whole closure. Unpinned 2026-08-22: head
    # carries tailscale 1.98.10, which builds, and vaultwarden 1.37.1, which
    # keeps the >= 1.37.0 floor that Bitwarden clients 2026.7.0+ require.
    # Update just it with `nix flake update nixpkgs`.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    # The workstations' nixpkgs. Same branch, separate input so a server-side
    # pin never gates a workstation's kernel or Plasma — that split is about
    # server vs workstation, not desktop vs laptop, so both workstations share
    # this one input. They run the same Plasma/gaming/Claude stack, and moving
    # them together keeps a bad revision from being true on one and false on
    # the other. Update just it with `nix flake update nixpkgs-workstation`.
    nixpkgs-workstation.url = "github:nixos/nixpkgs/nixos-26.05";

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
      inputs.nixpkgs.follows = "nixpkgs-workstation"; # workstations only
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
      self,
      nixpkgs,
      nixpkgs-workstation,
      agenix,
      claude-code,
      claude-desktop,
      ...
    }:
    let
      # Every host here is x86_64. genAttrs rather than a flake-utils input:
      # this is the whole of what that input would provide, and an input is a
      # lockfile entry that has to be kept moving.
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # The two packages this repo carries that nixpkgs does not. Named and
      # lifted out of `shared` rather than inlined there, so they are reachable
      # from outside a system build: `nix build .#aurral` now iterates on the
      # derivation directly, which is what packaging work needs. The hosts
      # still receive them through `shared` exactly as before.
      ourPackages = final: _prev: {
        headroom = final.callPackage ./pkgs/headroom { };
        aurral = final.callPackage ./pkgs/aurral { };
      };

      # Backs the packages/checks/formatter/devShells outputs only. The HOSTS
      # do not use this — each builds these against its own nixpkgs via the
      # overlay, so a workstation's headroom comes from nixpkgs-workstation.
      # This is the one representative build for `nix build`, CI and nixpkgs
      # iteration; it uses the server input because aurral is deployed from it.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ ourPackages ];
        };

      # Applied to every host. agenix rides the overlay rather than
      # agenix.packages: the latter is built from the `nixpkgs` input, which
      # would drag the server's closure (a second glibc, a second nix) onto a
      # workstation. The overlay builds it against each host's own pkgs; the
      # agenix version is fixed by the flake input either way.
      shared =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            claude-code.overlays.default
            agenix.overlays.default
            ourPackages
          ];
          environment.systemPackages = [ pkgs.agenix ];
        };

      # Both workstations run Claude Desktop. The module, not just the overlay:
      # Cowork's micro-VM needs OVMF at FHS paths, virtiofsd, vhost_vsock and
      # kvm group membership, which a package-only install skips. Each host
      # overrides `package =` so this pulls no closure from claude-desktop's own
      # nixpkgs.
      claudeDesktop = [
        claude-desktop.nixosModules.default
        { nixpkgs.overlays = [ claude-desktop.overlays.default ]; }
      ];
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

        # Carries both agenix roles: it decrypts its own secrets at activation
        # (samba-client.age, via the host key in keys.nix) and it holds the
        # `admin` key that edits every secret, including the server's.
        frame-automata = nixpkgs-workstation.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/frame-automata
            agenix.nixosModules.default
            shared
          ]
          ++ claudeDesktop;
        };

        # No agenix.nixosModules.default: this host declares no age.secrets, and
        # deliberately holds no key in keys.nix — its disk is unencrypted, so a
        # host key there would be a decryption capability anyone with the laptop
        # could use. It gets the agenix CLI from `shared` and nothing else.
        frame-automobile = nixpkgs-workstation.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/frame-automobile
            shared
          ]
          ++ claudeDesktop;
        };

        # The girlfriend's desktop (Ryzen 5800X3D / RTX 2070 Super). Same
        # workstation nixpkgs as the other two, so all three interactive
        # machines move together and a revision is never good on one and bad on
        # another. It imports modules/workstation but none of its dev-*.nix
        # layers: dev-tools.nix is Thomas's editor/CLI set and
        # dev-databases.nix his Traceway databases, and this is not his machine.
        #
        # No agenix.nixosModules.default and no key in keys.nix — not as a
        # standing decision the way frame-automobile's is, just nothing to
        # decrypt yet. Enrolling a host key is step one of giving it the Samba
        # shares (README), and that is when the module gets added.
        #
        # No claudeDesktop either: nobody here is running Cowork micro-VMs.
        wonudesktop = nixpkgs-workstation.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/wonudesktop
            shared
          ];
        };
      };

      # Consumable from outside this repo: another flake taking this one as an
      # input gets aurral and headroom from
      # `inputs.nix-config.overlays.default`. `shared` above applies the same
      # value, so the hosts and any consumer are building the same expression.
      overlays.default = ourPackages;

      # `nix build .#aurral`. Packaging work is edit-build-repeat against one
      # derivation, and before this output the only way to build either of
      # these was to build a whole system closure that contained it.
      packages = forAllSystems (system: {
        inherit (pkgsFor system) aurral headroom;
      });

      # `nix fmt`. nixfmt is the RFC 166 formatter and the one nixpkgs CI
      # enforces, so a file formatted here is already conformant when it gets
      # copied into a nixpkgs PR. (nixfmt-rfc-style is an alias for it now.)
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      # The gate, to be built one attr at a time.
      #
      # `nix flake check` itself is RED and stays red until wonudesktop is
      # installed — it walks `nixosConfigurations` on its own, independently of
      # this attrset, and hits that host's hardware-configuration.nix throw.
      # Nothing here can suppress that; there is no per-output exclusion. So
      # this attrset is what .github/workflows/ci.yml drives explicitly, e.g.
      #   nix build .#checks.x86_64-linux.formatting
      # Switch CI back to a plain `nix flake check` the day that host lands.
      #
      # host-* are the three machines that exist. Add wonudesktop to both this
      # list and the CI eval loop at the same time.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          inherit (self.packages.${system}) aurral headroom;
          host-wheezertbts = self.nixosConfigurations.wheezertbts.config.system.build.toplevel;
          host-frame-automata = self.nixosConfigurations.frame-automata.config.system.build.toplevel;
          host-frame-automobile = self.nixosConfigurations.frame-automobile.config.system.build.toplevel;

          # Keeps the tree nixfmt-clean. `${self}` is the flake source — every
          # tracked file, no .git — so an edit anywhere re-runs this.
          #
          # The two hardware-configuration.nix files are covered too, and
          # nixos-generate-config does NOT emit nixfmt-clean output: after
          # regenerating one (wonudesktop's is still to come), run `nix fmt`
          # before committing or this goes red on a file you did not hand-write.
          formatting = pkgs.runCommandLocal "check-nixfmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            nixfmt --check $(find ${self} -name '*.nix')
            touch $out
          '';
        }
      );

      # `nix develop`, or automatically via the .envrc — programs.direnv is
      # already on in modules/workstation/dev-tools.nix, and nix-direnv
      # GC-roots this closure so modules/workstation's nix.gc cannot collect a
      # toolchain this checkout still wants.
      #
      # A shell rather than more systemPackages in dev-tools.nix: this is the
      # toolchain for working ON nixpkgs, which happens in a checkout. It has
      # no business in the system closure of every machine Thomas administers.
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nixfmt # the nixpkgs house format; same binary `nix fmt` uses
              nixpkgs-review # `nixpkgs-review pr <n>` — build what a PR rebuilds
              nix-init # scaffold a derivation from an upstream URL
              nurl # fetcher expression + hash for a repo URL
              nix-update # bump version + hash in an existing derivation
              nixpkgs-lint-community # catches what a nixpkgs reviewer would
            ];
          };
        }
      );
    };
}
