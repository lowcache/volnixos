{
  description = "Vol NixOS - Vol(atile) Nix OS by LowCache [github.com/lowcache/volnixos.git]";
  inputs = {
    # The lock is deliberately pinned AHEAD of the nixos-unstable channel rev
    # (f4a6f27, 2026-09-17). The channel rev b1b8759 carries playwright 1.63.0
    # but not nixpkgs 67bf9043 "playwright-webkit: add missing libmanette", so
    # playwright-webkit fails auto-patchelf and takes playwright-mcp ->
    # home-manager-path -> toplevel down with it. f4a6f27 is a strict
    # fast-forward of b1b8759 and hydra has the fixed webkit cached, so the
    # kernel cache-hit gate still passes. Drop the pin -- plain
    # `nix flake update nixpkgs` -- once nixos-unstable includes 67bf9043.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Noctalia v5 (C++/native shell). follows nixpkgs per decision (source build,
    # no Cachix). Wired via home/noctalia.nix (homeModules.default).
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pinned v4.7.7 backup (emergency rollback). Kept COMMENTED so an unused input
    # can't fail `nix flake lock`. To use: uncomment, lock, point home/noctalia.nix
    # package at inputs.noctalia-stable.packages.${system}.default.
    # noctalia-stable = {
    #   url = "github:noctalia-dev/noctalia?ref=v4.7.7";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # lix-module input removed: nixpkgs ships lix natively (lixPackageSets) and
    # the module's release branches lag nixpkgs' supported versions (release-2.93
    # vs nixpkgs stable 2.95). nix.package is set in nixos/modules/nix-settings.nix.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    volinit = {
      url = "github:lowcache/volinit";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    memd = {
      url = "github:lowcache/memd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Package set for the phone. Deliberately NOT our nixpkgs.
    #
    # glibc 2.42 reimplemented isatty()/tcgetattr() on top of the TCGETS2 ioctl
    # (termios2, arbitrary baud rates). Android's SELinux ioctl allowlist for
    # untrusted_app permits TCGETS but not TCGETS2, so on-device it returns
    # EACCES. Every glibc-2.42 binary therefore concludes it has no terminal:
    # bash and fish start, decide they are non-interactive, print no prompt and
    # silently read commands from the pty. It reads exactly like a hang.
    # Measured on-device 2026-08-02 against a live pty (nix-on-droid, Android 16):
    #   TCGETS  0x5401     OK        tty (coreutils 9.5, glibc 2.40) -> /dev/pts/0
    #   TCGETS2 0x802C542A EACCES    tty (coreutils 9.11, glibc 2.42) -> not a tty
    # glibc is the root of the package graph, so patching it means rebuilding all
    # of nixpkgs on a phone. Pinning to a release with glibc 2.40 costs nothing
    # and stays fully cached. Revisit once glibc falls back to TCGETS on EACCES.
    nixpkgs-droid.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager-droid = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-droid";
    };
    # Nix-on-Droid: the aarch64 Android target (`nixOnDroidConfigurations.default`).
    # No release branch is current — release-24.05 is the newest tag and it is
    # ~2 years behind, so track master and point its nixpkgs/home-manager at the
    # droid pin above rather than at ours.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
      inputs = {
        nixpkgs.follows = "nixpkgs-droid";
        home-manager.follows = "home-manager-droid";
        # Docs/formatter-only inputs. We never evaluate nix-on-droid's own
        # `formatter`/`checks`/docs outputs, so drop them rather than carry
        # extra locked revisions the phone would have to resolve.
        nix-formatter-pack.follows = "";
        nmd.follows = "";
        nixpkgs-docs.follows = "nixpkgs-droid";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      username = "lowcache";
      system = "x86_64-linux";
      droidSystem = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.volnix = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs username; };
        modules = [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          {
            nixpkgs.overlays = [
              inputs.nix-cachyos-kernel.overlays.pinned
              inputs.nur.overlays.default
              inputs.llm-agents.overlays.shared-nixpkgs
              (import ./nixos/overlays/brave.nix)
              (import ./nixos/overlays/pandas-stubs.nix)
              # ollama-cuda pin dropped 2026-08-27; CI green since, overlay removed.
            ];
          }
          ./nixos
          ./nixos/hardware-configuration.nix
          inputs.lanzaboote.nixosModules.lanzaboote
          inputs.impermanence.nixosModules.impermanence
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.${username} = import ./home;
            };
          }
        ];
      };

      # Nix-on-Droid target. Built and switched ON THE PHONE
      # (`nix-on-droid switch --flake .`) — there is no aarch64 emulation on
      # volnix, so the laptop can only evaluate this, not build it
      # (`make droid-check`).
      nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
        # inputs.nixpkgs-droid, NOT nixpkgs — see the input comment: glibc 2.42's
        # TCGETS2 isatty() is denied by Android SELinux, which leaves every
        # interactive shell promptless.
        pkgs = import inputs.nixpkgs-droid {
          system = droidSystem;
          overlays = [
            # Recommended by upstream: supplies the on-device packages
            # (proot-static, termux shims) the nix-on-droid modules reference.
            inputs.nix-on-droid.overlays.default
            # Same overlay volnix uses, so `pkgs.llm-agents.*` resolves on the
            # phone too. llm-agents.nix builds aarch64-linux; the substituter it
            # publishes to is declared in droid/default.nix.
            inputs.llm-agents.overlays.shared-nixpkgs
            # Tools that exist only in unstable, rebuilt against the pinned
            # (glibc 2.40) package set. See droid/backports.nix — building any
            # directory source on-device needs a proot workaround, and one of
            # them needs a newer rustc than 25.11 ships.
            (import ./droid/backports.nix {
              unstable = inputs.nixpkgs;
              unstablePkgs = import inputs.nixpkgs {
                system = droidSystem;
                config.allowUnfree = true;
              };
              nix-on-droid-src = inputs.nix-on-droid;
            })
          ];
          config.allowUnfree = true;
        };
        modules = [ ./droid ];
        extraSpecialArgs = {
          inherit (inputs) nix-on-droid;
        };
        home-manager-path = inputs.home-manager-droid.outPath;
      };

      # Add this to allow building/running the VM packages
      packages.${system} = {
        net-gate =
          self.nixosConfigurations.volnix.config.microvm.vms.net-gate.config.config.microvm.declaredRunner;
        tailscale-vm =
          self.nixosConfigurations.volnix.config.microvm.vms.tailscale.config.config.microvm.declaredRunner;
      };

      # Reusable project scaffolds: `nix flake init -t ~/.nix-config#ruby`.
      # Not per-system — a template is just a directory of files to copy.
      templates = {
        go = {
          path = ./templates/go;
          description = "Go devShell + guarded buildGoModule";
        };
        hugo = {
          path = ./templates/hugo;
          description = "Hugo site: hugo/go/wrangler + reproducible site build";
        };
        lua = {
          path = ./templates/lua;
          description = "Lua plugin devShell (lua5_4, shellcheck, stylua)";
        };
        luau = {
          path = ./templates/luau;
          description = "Luau plugin devShell + luau-lsp analyze gate";
        };
        python = {
          path = ./templates/python;
          description = "Python devShell (withPackages: pytest, ruff)";
        };
        ruby = {
          path = ./templates/ruby;
          description = "Ruby devShell (bundler) + reproducible bundlerEnv build";
        };
        # No `default` on purpose. With six templates, a bare
        # `nix flake init -t ~/.nix-config` would silently scaffold whichever
        # one won the coin toss into the wrong project. Name the language.
      };

      # `nix fmt` — nixfmt (RFC 166, the official formatter), treefmt-wrapped so
      # it formats the whole tree and respects the git index (untracked files
      # like dots/gemini worktrees are skipped).
      formatter.${system} = pkgs.nixfmt-tree;

      # `nix flake check` gates: formatting + lint. ${self} is the git-tracked
      # source only, so generated/untracked .nix files are out of scope.
      checks.${system} = {
        formatting = pkgs.runCommand "check-formatting" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          find ${self} -name '*.nix' -exec nixfmt --check {} +
          touch $out
        '';
        lint =
          pkgs.runCommand "check-lint"
            {
              nativeBuildInputs = [
                pkgs.statix
                pkgs.deadnix
              ];
            }
            ''
              statix check ${self}
              deadnix --fail ${self}
              touch $out
            '';
      };
    };
}
