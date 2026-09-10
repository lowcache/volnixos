# Vol NixOS Makefile
# Unifies system rebuilds, MicroVM guest management, SOPS secrets, and maintenance tasks.

# --- Configuration & Environment Defaults ---
HOST           ?= volnix
REBUILD_TMPDIR ?= $(HOME)/Storage/tmp
FLAKE_DIR      := /persist/home/lowcache/.nix-config

# --- Dotfiles Subtree Config ---
DOTS_PREFIX       ?= dots
DOTS_REMOTE       ?= dotfiles
DOTS_BRANCH       ?= main
DOTS_SPLIT_BRANCH ?= dots-history

# --- SOPS / Secret Management ---
# The secrets are split by TRUST BOUNDARY, and nixos/.sops.yaml encrypts the two
# files to different key sets: host-secrets.yaml to the admin user AND the host
# key; vm-secrets.yaml to the host key ONLY, because net-gate shares the host
# SSH key over virtio-fs and anything in that file is therefore readable by the
# guest. Editing the wrong file puts a secret behind the wrong keys.
#
# These paths MUST name files that already exist. `sops <path>` on a missing
# path CREATES it rather than failing, so a stale default here does not error —
# it silently writes a new encrypted file that nothing reads, and the rebuild
# then fails at activation hunting a secret that went somewhere else. That is
# exactly what the old default did: it still said nixos/secrets.yaml after the
# file was split into host- and vm-secrets, so every sops-edit was one keystroke
# from a decoy. The targets below assert existence for that reason.
SOPS_FILE         ?= nixos/host-secrets.yaml
SOPS_VM_FILE      ?= nixos/vm-secrets.yaml
# $(HOME), not ~ — a tilde inside a make variable only survives because the
# shell happens to expand it in a leading assignment; it breaks the moment the
# value is used anywhere else, such as the test -f guards below.
SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

# --- Documentation site ---
# The wiki is its own repo now (~/CodeRepo/blogs/wiki), alongside the other
# sites. Its serve/build/deploy targets live in that repo's Makefile. The `docs`
# and `site` entries here were symlinks into it and have been removed, along
# with the duplicated mkdocs.yml and wrangler.toml.

# --- All Targets Declared PHONY ---
.PHONY: help switch switch-detached build test dry-activate boot \
        droid-check droid-plan droid-switch \
        run-netgate run-tailscale \
        sops-edit sops-edit-vm sops-rekey sops-view sops-view-vm \
        backup backup-force backup-mount backup-umount \
        check fmt update update-nixpkgs trash \
        git comm push \
        dots-log dots-split dots-remote dots-push dots-pull

.DEFAULT_GOAL := help

## :help: ..........: Display available targets and descriptions
help:
	@echo ""	
	@echo "Vol NixOS Helper Makefile"
	@echo "Usage- make [command]"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) | column -t -s ':' -o '' -C color=yellow,right -C color=white,left -C color=white,left -C color=green

# ==============================================================================
# System Operations
# ==============================================================================
## System Operations
## :switch: ..........: Rebuild and switch system live (Default HOST- volnix)
switch:
	sudo TMPDIR=$(REBUILD_TMPDIR) nixos-rebuild switch --flake .#$(HOST) --option fallback true

## :switch-detached: ..........: Switch as a detached system unit (survives session manager/greetd teardowns)
switch-detached:
	sudo systemd-run --collect --unit=nixos-switch \
		--setenv=TMPDIR=$(REBUILD_TMPDIR) \
		--setenv=SUDO_UID=$$(id -u) \
		--setenv=PATH=/run/current-system/sw/bin:/run/wrappers/bin \
		nixos-rebuild switch --flake $(FLAKE_DIR)/#$(HOST)
	@echo ""
	@echo "++ Switch running detached as system unit 'nixos-switch'."
	@echo "++ Follow:  journalctl -u nixos-switch -f"
	@echo "++ Status:  systemctl status nixos-switch"

## :build: ..........: Build system configuration without switching
build:
	TMPDIR=$(REBUILD_TMPDIR) nixos-rebuild build --flake .#$(HOST)

## :test: ..........: Temporarily switch to configuration (no boot entry)
test:
	sudo TMPDIR=$(REBUILD_TMPDIR) nixos-rebuild test --flake .#$(HOST)

## :dry-activate: ..........: See what service transitions will happen
dry-activate:
	sudo TMPDIR=$(REBUILD_TMPDIR) nixos-rebuild dry-activate --flake .#$(HOST)

## :boot: ..........: Stage the rebuild for the next boot
boot:
	sudo TMPDIR=$(REBUILD_TMPDIR) nixos-rebuild boot --flake .#$(HOST)

# ==============================================================================
# Nix-on-Droid (aarch64 phone target)
# ==============================================================================
# The phone builds and switches itself — volnix has no aarch64 emulation, so
# these laptop-side targets are evaluation gates only. `droid-switch` is what
# you run ON the phone, from a clone of this repo.
#
# `--impure` is required: nix-on-droid's own CLI passes it too, because the
# bootstrap proot binary is referenced via `builtins.storePath`.

# NOTE: the '#' must be escaped — in a Make variable assignment an unescaped
# '#' starts a comment and would silently truncate this to '.'.
DROID_ATTR := .\#nixOnDroidConfigurations.default
## Nix-On-Droid
## :droid-check: ..........: Evaluate the phone's Home Manager layer from the laptop (no build)
droid-check:
	@echo "==Evaluating $(DROID_ATTR) home-manager layer (aarch64-linux)=="
	nix eval --impure --raw \
		'$(DROID_ATTR).config.home-manager.config.home.activationPackage.drvPath'
	@echo ""
	@echo "++ Evaluates clean. The system layer's uid/gid probe is import-from-"
	@echo "++ derivation and can only run on the device."

## :droid-plan: ..........: List what the phone would fetch vs. compile (dry-run, laptop-side)
droid-plan:
	nix build --impure --dry-run \
		'$(DROID_ATTR).config.home-manager.config.home.activationPackage'

## :droid-switch: ..........: Build+activate on the PHONE (run this inside Nix-on-Droid)
droid-switch:
	nix-on-droid switch --flake .

# ==============================================================================
# MicroVM Guest Operations
# ==============================================================================
## MicroVM
## :run-netgate: ..........: Start the Tor net-gate MicroVM runner
run-netgate:
	nix run .#net-gate

## :run-tailscale: ..........: Start the Tailscale-vm MicroVM runner
run-tailscale:
	nix run .#tailscale-vm

# ==============================================================================
# Secrets Management (SOPS / Age)
# ==============================================================================
## Secret Management
## :sops-edit: ..........: Decrypt and edit host secrets (nixos/host-secrets.yaml)
sops-edit:
	@test -f "$(SOPS_FILE)" || { echo "no such secrets file: $(SOPS_FILE)"; \
	  echo "(sops would CREATE it — refusing, check the path)"; exit 1; }
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops $(SOPS_FILE)

## :sops-edit-vm: ..........: Decrypt and edit VM secrets (host key only)
sops-edit-vm:
	@test -f "$(SOPS_VM_FILE)" || { echo "no such secrets file: $(SOPS_VM_FILE)"; \
	  echo "(sops would CREATE it — refusing, check the path)"; exit 1; }
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops $(SOPS_VM_FILE)

## :sops-rekey: ..........: Re-encrypt BOTH files against the keys in .sops.yaml
sops-rekey:
	@for f in $(SOPS_FILE) $(SOPS_VM_FILE); do \
	  test -f "$$f" || { echo "missing: $$f"; exit 1; }; \
	  echo "== rekeying $$f"; \
	  SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops updatekeys "$$f" || exit 1; \
	done

## :sops-view: ..........: Print decrypted host secrets without an editor
sops-view:
	@test -f "$(SOPS_FILE)" || { echo "no such secrets file: $(SOPS_FILE)"; exit 1; }
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d $(SOPS_FILE)

## :sops-view-vm: ..........: Print decrypted VM secrets without an editor
sops-view-vm:
	@test -f "$(SOPS_VM_FILE)" || { echo "no such secrets file: $(SOPS_VM_FILE)"; exit 1; }
	SOPS_AGE_KEY_FILE=$(SOPS_AGE_KEY_FILE) sops -d $(SOPS_VM_FILE)

# ==============================================================================
# External-Drive Backup
# ==============================================================================
# Same systemd unit udev starts on plug-in, so a manual run and an automatic one
# are the same code path — there is no second implementation to drift.
## Backup
## :backup: ..........: Run the external-drive backup now (obeys the 12h cooldown)
backup:
	@test -e /dev/disk/by-label/VOLBAK || { \
	  echo "++ VOLBAK not found - is the drive plugged in?"; exit 1; }
	@sudo systemctl start --wait vol-backup.service; rc=$$?; \
	journalctl -u vol-backup.service -n 25 --no-pager -o cat; \
	exit $$rc

## :backup-force: ..........: Run it now even if a backup succeeded within the cooldown
backup-force:
	sudo rm -f /var/lib/vol-backup/last-success
	@$(MAKE) --no-print-directory backup

## :backup-mount: ..........: Mount the repo for manual restic work (restore, snapshots)
backup-mount:
	sudo systemctl start mnt-backup.mount
	@echo "++ /mnt/backup mounted. Try: restic-volnix snapshots"
	@echo "++ Browse a snapshot: mkdir -p /tmp/r && restic-volnix mount /tmp/r"

## :backup-umount: ..........: Unmount and power down the drive
backup-umount:
	-sudo systemctl stop mnt-backup.mount mnt-models.mount
	@sync; echo "++ Drive unmounted; safe to remove."

# ==============================================================================
# Flake & Code Maintenance
# ==============================================================================
## Flake & Code Maintenance
## :check: ..........: Check flake lock and schema validity
check:
	nix flake check
	@echo "==Dead Code & Antipattern Checks=="
	@echo "==Running Deadnix=="
	@deadnix --fail .
	@echo "==Running Statix Check=="
	@statix check .

## :fmt: ..........: Auto-format all Nix expressions
fmt:
	nix fmt
	@echo "==Statix Fix=="
	@statix fix .

## :update: ..........: Update all flake inputs
update:
	nix flake update

## :update-nixpkgs: ..........: Update only the nixpkgs input
update-nixpkgs:
	nix flake update nixpkgs

## :trash: ..........: Delete system profile generations older than 7 days and clean store
trash:
	@echo "++ Deleting system profile generations older than 7 days..."
	sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations 7d
	@echo "++ Running Nix store garbage collection..."
	nix-store --gc

# ==============================================================================
# Git Operations
# ==============================================================================
## Git Ops
## :git: ..........: Automated procedure to commit changes and sync with remote
git:
	@run() { $(MAKE) --no-print-directory push && $(MAKE) --no-print-directory comm && $(MAKE) --no-print-directory push; }; \
	if ssh-add -l >/dev/null 2>&1; then \
		run; \
	else \
		eval "$$(ssh-agent -s)" >/dev/null 2>&1; \
		trap 'kill "$$SSH_AGENT_PID" 2>/dev/null' EXIT; \
		echo "++ Starting ssh-agent (passphrase required once)..."; \
		ssh-add ~/.ssh/id_ed25519 || exit 1; \
		run; \
	fi && echo "++ Git Repo Updated."
# Hand the run off to the background poller instead of blocking here.
# `gh run watch` held the terminal for the whole build to print a spinner;
# ci-poll writes the same progress into the starship prompt (see
# home/scripts.nix and dots/starship/starship.toml) and returns now. `make
# ci` below is still the way to sit and watch a run in the foreground.
	@command -v ci-poll >/dev/null 2>&1 && ci-poll || \
	  echo "++ ci-poll not on PATH yet (needs a switch); 'make ci' watches in the foreground."

## :ci: ..........: Watch the CI run for HEAD in the foreground (blocks; 'make git' polls instead)
ci:
	@command -v gh >/dev/null 2>&1 || { echo "++ gh not on PATH; skipping CI watch."; exit 0; }; \
	sha=$$(git rev-parse HEAD); short=$$(git rev-parse --short HEAD); \
	printf "++ Locating CI run for %s" "$$short"; \
	id=""; \
	for i in $$(seq 1 20); do \
		id=$$(gh run list --commit "$$sha" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null); \
		[ -n "$$id" ] && break; \
		printf "."; sleep 3; \
	done; \
	echo ""; \
	if [ -z "$$id" ]; then \
		echo "++ No run for $$short - docs-only pushes match paths-ignore (**.md, docs/, assets/, LICENSE)."; \
		exit 0; \
	fi; \
	gh run view "$$id" --json url --jq '"++ " + .url'; \
	st=$$(gh run view "$$id" --json status --jq '.status'); \
	if [ "$$st" = "completed" ]; then \
		gh run view "$$id" --json conclusion --jq '"++ already finished: " + .conclusion'; \
		[ "$$(gh run view "$$id" --json conclusion --jq '.conclusion')" = "success" ] || exit 1; \
		exit 0; \
	fi; \
	echo "++ Ctrl-C detaches; the build keeps running on the runner."; \
	echo "++ cachix:volnixos upload is cachix-action's post step, so it finishes last."; \
	gh run watch "$$id" --compact --exit-status

## :comm: ..........: Scan repo, stage changes, and prompt for commit message
comm:
	@echo "++ Scanning Repo..."; \
	git add .; \
	echo "++ Staging Commit..."; \
	if read -p "++ Enter Commit Message: " cm && [ -n "$$cm" ]; then \
		echo ""; \
		git commit -m "$$cm" || true; \
	else \
		echo "++ ERROR: Commit Message Invalid."; \
		echo "++ Aborting..."; \
		exit 1; \
	fi

## :push: ..........: Push local commits to remote using ssh-agent
push:
	@echo "++ Pushing to Remote..."; \
	if ssh-add -l >/dev/null 2>&1; then \
		git push; \
	else \
		echo "++ No usable ssh-agent found; starting one (passphrase required)..."; \
		eval "$$(ssh-agent -s)" >/dev/null 2>&1; \
		ssh-add ~/.ssh/id_ed25519 && git push; rc=$$?; \
		kill "$$SSH_AGENT_PID" 2>/dev/null; \
		exit $$rc; \
	fi

# ==============================================================================
# Dotfiles Subtree Operations
# ==============================================================================
## Dotfiles
## :dots-log: ..........: Show git log scoped to dots/ prefix
dots-log:
	git log --oneline -- $(DOTS_PREFIX)

## :dots-split: ..........: Regenerate the projection branch of dots/
dots-split:
	@echo "Regenerating '$(DOTS_SPLIT_BRANCH)' projection of $(DOTS_PREFIX)/ ..."
	-@git branch -D $(DOTS_SPLIT_BRANCH) >/dev/null 2>&1 || true
	git subtree split --prefix=$(DOTS_PREFIX) -b $(DOTS_SPLIT_BRANCH)

## :dots-remote: ..........: Add standalone dotfiles remote (Usage- make dots-remote URL=<url>)
dots-remote:
	@test -n "$(URL)" || { echo "Usage: make dots-remote URL=<git-url>"; exit 1; }
	git remote add $(DOTS_REMOTE) "$(URL)"
	@echo "Added remote '$(DOTS_REMOTE)' -> $(URL)"

## :dots-push: ..........: Publish dots/ history to remote
dots-push:
	git subtree push --prefix=$(DOTS_PREFIX) $(DOTS_REMOTE) $(DOTS_BRANCH)

## :dots-pull: ..........: Merge changes from remote back into dots/
dots-pull:
	git subtree pull --prefix=$(DOTS_PREFIX) $(DOTS_REMOTE) $(DOTS_BRANCH)

# ==============================================================================
# Documentation Wiki
# ==============================================================================
# Moved out. The wiki is a standalone repo at ~/CodeRepo/blogs/wiki with its own
# Makefile:
#   make -C ~/CodeRepo/blogs/wiki serve       # live preview
#   make -C ~/CodeRepo/blogs/wiki build       # strict build to ./site
#   make -C ~/CodeRepo/blogs/wiki deploy-cf   # publish to Cloudflare
