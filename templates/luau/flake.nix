{
  description = "Luau development environment: analyser, formatter, and offline gates";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      # =====================================================================
      # Project knobs.
      # =====================================================================

      # Type definitions fed to the analyser. This file is INPUT to the
      # analyser, not a target of it, so it is excluded from the entry list.
      # Leave as-is for Noctalia plugins.
      definitionsFile = "noctalia.d.luau";

      # Extra tools beyond luau/stylua/python3, as nixpkgs attribute names.
      extraTools = [ ];

      # Offline gates beyond the built-in analyser. See the README.
      #   checkCommands = {
      #     i18n = "python3 scripts/check-i18n.py";
      #     specs = "for s in tests/*_spec.py; do python3 \"$s\" || exit 1; done";
      #     widget-specs = "bash scripts/run-widget-specs.sh .";
      #   };
      checkCommands = { };

      # =====================================================================

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      inherit (nixpkgs) lib;

      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The whole toolchain the entries need. Nothing here runs Noctalia: every
      # check below is offline and hermetic, which is the point -- the live
      # shell is where behaviour is confirmed, this is where syntax and
      # contract are.
      toolchain =
        pkgs:
        [
          pkgs.luau # the interpreter the spec suites run under
          # luau-lsp, NOT the bare luau-analyze binary. luau-analyze has no
          # --definitions flag (luau 0.735 accepts only --formatter, --mode,
          # --solver, --timetrace); passing it makes every host global read as
          # "Unknown global" and the gate exits 1 no matter how clean the code
          # is. luau-lsp's analyze subcommand is the one that loads definitions.
          pkgs.luau-lsp
          pkgs.stylua # format the entries
          pkgs.python3 # the hooks, the shim, and the spec suites
        ]
        ++ map (name: pkgs.${name}) extraTools;

      # Entries discovered at evaluation time rather than listed by hand. The
      # flake this was lifted from carried a nine-name string, which meant a
      # tenth entry added later went unanalysed with the gate still green.
      entryFiles = builtins.filter (name: name != definitionsFile) (
        builtins.attrNames (
          lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".luau" name) (builtins.readDir ./.)
        )
      );

      hasEntries = builtins.pathExists (./. + "/${definitionsFile}") && entryFiles != [ ];

      mkCheck =
        pkgs: name: command:
        pkgs.runCommand "check-${name}" { nativeBuildInputs = toolchain pkgs; } ''
          cp -r ${./.} src
          chmod -R u+w src
          cd src
          ${command}
          touch $out
        '';

      # Parse and typecheck every entry. The gate that did not exist when a
      # call to a not-yet-declared local shipped and took a widget down on
      # load: the call resolves to an unknown global and the analyser exits
      # non-zero. Inert until both the definitions file and at least one entry
      # exist, so a freshly stamped project still evaluates.
      mkChecks =
        pkgs:
        lib.optionalAttrs hasEntries {
          analyze =
            mkCheck pkgs "analyze"
              "luau-lsp analyze --definitions=${definitionsFile} ${lib.concatStringsSep " " entryFiles}";
        }
        // builtins.mapAttrs (mkCheck pkgs) checkCommands;
    in
    {
      # No packages output. Luau entries are interpreted and loaded by a host
      # (Noctalia); there is nothing to build into the store.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = toolchain pkgs;
          shellHook = ''
            echo "luau dev shell"
            echo "  nix flake check   luau-lsp analyze + your checkCommands gates"
            echo "  stylua *.luau     format (opt-in; deliberately not a gate)"
          '';
        };
      });

      checks = forAllSystems mkChecks;

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
