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

      # The single list the packages and checks outputs both select with.
      # attrNames does not force the values, so the dummy arguments are never
      # looked at. Deriving the names and then selecting from the real,
      # overlaid pkgs is deliberate: applying the overlay as `ourPackages pkgs
      # pkgs` would pass the final package set as `prev`, so the first
      # `prev.foo.overrideAttrs`-shaped entry anyone adds — the normal way to
      # carry a patch — would resolve `prev` to the already-overridden
      # attribute and hit infinite recursion. The hosts would keep building,
      # since they go through a real fixpoint, making it look like a broken
      # output rather than a broken overlay.
      ourPackageNames = builtins.attrNames (ourPackages { } { });

      # Backs the packages/checks/formatter/devShells outputs only. The HOSTS
      # do not use this — each builds these against its own nixpkgs via the
      # overlay, so a workstation's headroom comes from nixpkgs-workstation.
      # This is the one representative build for `nix build`, CI and nixpkgs
      # iteration; it uses the server input because aurral is deployed from it.
      #
      # headroom ships from BOTH inputs (hosts/wheezertbts/default.nix and
      # modules/workstation/dev-tools.nix), so checks.headroom covers the
      # server build only. That gap is empty while both inputs sit on the same
      # branch and reopens the day `nixpkgs` gets pinned again — a workstation
      # rebuild is what catches it, not CI.
      #
      # An attrset, not a bare function: Nix memoizes attribute selection but
      # NOT function application, so `pkgsFor` as a function meant packages,
      # checks, formatter and devShells each evaluated their own nixpkgs
      # fixpoint. Measured across those four outputs: 2.20s CPU / 500MB before,
      # 1.17s / 198MB after.
      pkgsBySystem = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [ ourPackages ];
          # Matches modules/common/default.nix, which sets this for all four
          # hosts. Without it the outputs evaluate under a DIFFERENT nixpkgs
          # config than every machine: the day something here gains an unfree
          # dependency, `nixos-rebuild` succeeds on all four hosts while
          # `nix build .#<pkg>`, `nix develop` and CI fail on the licence.
          config.allowUnfree = true;
        }
      );
      pkgsFor = system: pkgsBySystem.${system};

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
      #
      # Selecting by ourPackageNames rather than re-listing keeps ONE list: a
      # third package added to ourPackages appears here, in checks, and in CI
      # (which reads these attrNames) with no further edit.
      packages = forAllSystems (system: nixpkgs.lib.getAttrs ourPackageNames (pkgsFor system));

      # `nix fmt`. nixfmt is the RFC 166 formatter and the one nixpkgs CI
      # enforces, so a file formatted here is already conformant when it gets
      # copied into a nixpkgs PR.
      #
      # nixfmt-tree (nixfmt behind treefmt), NOT bare nixfmt: `nix fmt` with no
      # arguments passes NO arguments through, and bare nixfmt then reads
      # stdin — so it formats nothing and, on a terminal, blocks forever.
      # The tree wrapper is what makes the documented `nix fmt` walk the repo.
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      # The gate. CI drives these by name; see .github/workflows/ci.yml.
      #
      # Two separate reasons a bare `nix flake check` is not the entry point,
      # and only the first one ever goes away:
      #
      #   1. It walks `nixosConfigurations` independently of this attrset, so
      #      it hits wonudesktop's hardware-configuration.nix throw. No output
      #      here can suppress that — there is no per-output exclusion.
      #   2. It BUILDS every check (verified: --no-build is what makes it
      #      evaluate only). Once wonudesktop lands, host-* is four full NixOS
      #      closures, which is exactly what does not fit a CI runner's disk.
      #
      # So installing wonudesktop does NOT mean "switch CI back to nix flake
      # check" — reason 2 outlives reason 1. The steady state is what CI does
      # today: evaluate the host-* checks, build the rest.
      #
      # host-* are the three installed machines. Add wonudesktop here when its
      # hardware scan replaces the placeholder; CI derives its list from this
      # attrset, so that is the only edit.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          inherit (nixpkgs) lib;
          nixfmtSources = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.fileFilter (f: f.hasExt "nix") ./.;
          };
        in
        self.packages.${system}
        // {
          host-wheezertbts = self.nixosConfigurations.wheezertbts.config.system.build.toplevel;
          host-frame-automata = self.nixosConfigurations.frame-automata.config.system.build.toplevel;
          host-frame-automobile = self.nixosConfigurations.frame-automobile.config.system.build.toplevel;

          # Keeps the tree nixfmt-clean.
          #
          # The fileset narrows the input to .nix files only. Depending on
          # `${self}` instead would rebuild this on any tracked file — and 17%
          # of this repo's commits touch no .nix file at all (README.md and
          # CLAUDE.md are the churn), so that was a guaranteed spurious rerun
          # on a sixth of all pushes.
          #
          # Every hardware-configuration.nix is covered, and
          # nixos-generate-config does NOT emit nixfmt-clean output: after
          # regenerating one (wonudesktop's is still to come), run `nix fmt`
          # before committing or this goes red on a file you did not hand-write.
          #
          # Runs self.formatter itself — the same derivation `nix fmt` runs —
          # so the two genuinely cannot enforce different things. --ci is
          # treefmt's no-cache + fail-on-change mode.
          #
          # Copied to a writable dir first, and cd'd into, for one reason:
          # treefmt reports paths relative to its tree root. Run against the
          # store path directly it would name
          # /nix/store/<hash>-source/modules/... in a red build, which is not a
          # path anyone can open.
          formatting =
            pkgs.runCommandLocal "check-nixfmt" { nativeBuildInputs = [ self.formatter.${system} ]; }
              ''
                cp -r ${nixfmtSources} tree
                chmod -R u+w tree
                cd tree
                treefmt --ci --tree-root .
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
