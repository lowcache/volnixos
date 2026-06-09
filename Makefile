# Vol NixOS Makefile
# Unifies system rebuilds, MicroVM guest management, and maintenance tasks

HOST ?= volnix

# --- Dotfiles subtree config (override on the command line if needed) ---
DOTS_PREFIX       ?= dots
DOTS_REMOTE       ?= dotfiles
DOTS_BRANCH       ?= main
DOTS_SPLIT_BRANCH ?= dots-history

# --- Colorscheme / theme workflow paths ---
II_DIR      := dots/illogical-impulse
THEMES_DIR  := $(II_DIR)/themes
SCRIPTS_DIR := $(II_DIR)/scripts
PYTHON      ?= python3

.PHONY: help switch build test dry-activate check fmt update update-nixpkgs gc run-netgate run-tailscale ghc \
        dots-log dots-split dots-remote dots-push dots-pull \
        theme-list theme-apply theme-check theme-new

help:
	@echo "Vol NixOS Helper Makefile"
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
	@echo "  make ghc            Adds changes and creates commit with generic description"
	@echo ""
	@echo "Dotfiles Subtree (independent history for $(DOTS_PREFIX)/, single repo):"
	@echo "  make dots-log       Show history scoped to $(DOTS_PREFIX)/ (read-only, no remote needed)"
	@echo "  make dots-split     (Re)generate the '$(DOTS_SPLIT_BRANCH)' projection branch of $(DOTS_PREFIX)/"
	@echo "  make dots-remote URL=<git-url>   Add the standalone '$(DOTS_REMOTE)' remote (one-time)"
	@echo "  make dots-push      Publish $(DOTS_PREFIX)/ history to $(DOTS_REMOTE)/$(DOTS_BRANCH)"
	@echo "  make dots-pull      Merge changes from $(DOTS_REMOTE)/$(DOTS_BRANCH) back into $(DOTS_PREFIX)/"
	@echo ""
	@echo "Colorscheme / Themes (in $(THEMES_DIR)):"
	@echo "  make theme-list                 List available themes"
	@echo "  make theme-apply THEME=<name>   Apply a theme by name (regenerates + reloads)"
	@echo "  make theme-check THEME=<name>   Validate a theme (hex + dangling refs + completeness)"
	@echo "  make theme-new NAME=\"My Theme\" [COLORS=\"#a #b ...\"] [FROM=<file>] [APPLY=1] [FORCE=1]"
	@echo "                                  Generate a new standards-compliant theme from colors"

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

ghc:
	git add .
	git commit -m "Minor Updates"

# --- Dotfiles subtree -------------------------------------------------------
# dots-log and dots-split work with no remote. dots-push/dots-pull need the
# remote set up once via `make dots-remote URL=...`.

dots-log:
	git log --oneline -- $(DOTS_PREFIX)

dots-split:
	@echo "Regenerating '$(DOTS_SPLIT_BRANCH)' projection of $(DOTS_PREFIX)/ ..."
	-@git branch -D $(DOTS_SPLIT_BRANCH) >/dev/null 2>&1 || true
	git subtree split --prefix=$(DOTS_PREFIX) -b $(DOTS_SPLIT_BRANCH)

dots-remote:
	@test -n "$(URL)" || { echo "Usage: make dots-remote URL=<git-url>"; exit 1; }
	git remote add $(DOTS_REMOTE) "$(URL)"
	@echo "Added remote '$(DOTS_REMOTE)' -> $(URL)"

dots-push:
	git subtree push --prefix=$(DOTS_PREFIX) $(DOTS_REMOTE) $(DOTS_BRANCH)

dots-pull:
	git subtree pull --prefix=$(DOTS_PREFIX) $(DOTS_REMOTE) $(DOTS_BRANCH)

# --- Colorscheme / theme workflow -------------------------------------------
# THEME is a bare name (no path, no .json). NAME is a display name for new themes.
# COLORS is a single quoted string of hex codes (bare '#' args become shell comments).

theme-list:
	@ls -1 $(THEMES_DIR)/*.json 2>/dev/null | xargs -n1 basename | sed 's/\.json$$//' || echo "(none)"

theme-apply:
	@test -n "$(THEME)" || { echo "Usage: make theme-apply THEME=<name>   (see: make theme-list)"; exit 1; }
	$(PYTHON) $(SCRIPTS_DIR)/apply_theme.py $(THEMES_DIR)/$(THEME).json true

theme-check:
	@test -n "$(THEME)" || { echo "Usage: make theme-check THEME=<name>   (see: make theme-list)"; exit 1; }
	$(PYTHON) $(SCRIPTS_DIR)/check_theme.py $(THEMES_DIR)/$(THEME).json

theme-new:
	@test -n "$(NAME)" || { echo "Usage: make theme-new NAME=\"My Theme\" [COLORS=\"#a #b\"] [FROM=<file>] [APPLY=1] [FORCE=1]"; exit 1; }
	$(PYTHON) $(SCRIPTS_DIR)/make_theme.py --name "$(NAME)" \
		$(if $(COLORS),--colors "$(COLORS)") \
		$(if $(FROM),--from "$(FROM)") \
		$(if $(APPLY),--apply) \
		$(if $(FORCE),--force)

