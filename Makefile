# Infernal NixOS Makefile
# Unifies system rebuilds, MicroVM guest management, and maintenance tasks

HOST ?= infernalnix

.PHONY: help switch build test dry-activate check fmt update update-nixpkgs gc run-netgate run-tailscale git

help:
	@echo "Infernal NixOS Helper Makefile"
	@echo ""
	@echo "System Operations:"
	@echo "  make switch         Rebuild and switch system live (Default HOST: $(HOST))"
	@echo "  make build          Build system configuration without switching"
	@echo "  make test           Temporarily switch to configuration (no boot entry)"
	@echo "  make dry-activate   See what service transitions will happen"
	@echo ""
	@echo "MicroVM Guest Operations:"
	@echo "  make run-netgate    Start the Tor net-gate MicroVM runner"
	@echo "  make run-tailscale  Start the Tailscale-vm MicroVM runner"
	@echo ""
	@echo "Flake & Code Maintenance:"
	@echo "  make check          Check flake lock and schema validity"
	@echo "  make fmt            Auto-format all Nix expressions using nixpkgs-fmt"
	@echo "  make update         Update all flake inputs"
	@echo "  make update-nixpkgs Update only the nixpkgs input"
	@echo "  make gc             Garbage collect older Nix store derivations"
	@echo "  make git            Adds changes and creates commit with generic description"

switch:
	sudo nixos-rebuild switch --flake .#$(HOST)

build:
	nixos-rebuild build --flake .#$(HOST)

test:
	sudo nixos-rebuild test --flake .#$(HOST)

dry-activate:
	sudo nixos-rebuild dry-activate --flake .#$(HOST)

run-netgate:
	nix run .#net-gate

run-tailscale:
	nix run .#tailscale-vm

check:
	nix flake check

fmt:
	find . -name "*.nix" -exec nixpkgs-fmt {} +

update:
	nix flake update

update-nixpkgs:
	nix flake update nixpkgs

gc:
	@echo "Deleting system profile generations older than 7 days..."
	sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations 7d
	@echo "Running Nix store garbage collection..."
	nix-store --gc

git:
	git add .
	git commit -m "Minor Updates"
	
