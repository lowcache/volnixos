{
  description = "Infernal NixOS - Imprecation & Impermanence. [github.com/lowcache/infernalnixos.git]";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";
    impermanence.url = "github:nix-community/impermanence";
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url ="git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lix-module = {
      url = "git+https://git.lix.systems/lix-project/nixos-module";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.url = "git+https://git.lix.systems/lix-project/lix";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, microvm, ... }@inputs: {
    nixosConfigurations.nondeus = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
      	{ nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ]; }
        ./nixos/configuration.nix
        ./nixos/hardware-configuration.nix
        inputs.lanzaboote.nixosModules.lanzaboote
        inputs.impermanence.nixosModules.impermanence
        inputs.lix-module.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.nondeus = import ./home;
        }
      ];
    };

    # Add this to allow building/running the VM package
    packages.x86_64-linux.net-gate = self.nixosConfigurations.nondeus.config.microvm.vms.net-gate.config.microvm.declaredRunner;
  };
}
