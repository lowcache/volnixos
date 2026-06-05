Title: Live Content

Description: Fetched live

Source: https://raw.githubusercontent.com/henrysipp/nix-setup/main/Makefile

---


HOST ?= $(shell hostname)

update: 
	sudo nix flake update
	
nixos:
	sudo nixos-rebuild switch --flake .#$(HOST) --impure

nixos-oma:
	sudo nixos-rebuild switch --flake .#$(HOST) --override-input omarchy path:/home/henrysipp/Developer/omarchy-nix

macos:
	sudo

