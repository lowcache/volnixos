{
  description = "infernalinit - Graphical shell initiation banner";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildNimPackage {
          pname = "infernalinit";
          version = "0.1.0";
          src = ./.;
          buildInputs = with pkgs; [ nim ];
          
          # We will embed the banner during build or look for it in a specific path
          # For now, let's assume we copy the tbann file into the package
          postPatch = ''
            mkdir -p assets
            cp ${../../tbann} assets/tbann
          '';

          nimFlags = [
            "--d:release"
            "--opt:speed"
          ];
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/infernalinit";
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ nim ];
        };
      });
}
