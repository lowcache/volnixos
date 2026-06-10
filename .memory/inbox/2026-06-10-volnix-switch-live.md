2026-06-10, confirmed by lowcache: the volnix switch is LIVE and the rebrand has been pushed.

- todo.md §0 (ACTIVATION DRIFT) is RESOLVED: the safe `switch --flake .#volnix` was performed (the 2026-06-09 "post-volnix switch" MicroVM verification already reflected this). The running system is no longer behind the repo. Close §0 / archive it.
- todo.md §4 (De-Infernal rebrand) remaining item "Activate: safe switch --flake .#volnix + reboot" is DONE. The rebrand commits have been pushed to github.com/lowcache/volnixos.git.
- §4 "Commit the rebrand" is done/pushed; only the optional cosmetic `mv ~/CodeRepo/infernal-init ~/CodeRepo/volinit` remains, plus any still-uncommitted unrelated working-tree changes (Makefile, dots/illogical-impulse/config.json, home/shell.nix, nixos/configuration.nix as of 2026-06-10).
- state.md should reflect: live hostname is `volnix`, running generation built from current repo HEAD lineage (26.11), mistakes.md#4 fromAi/outputs fix is now active on the machine.
- The §1 verifications (Ollama VRAM unload, Fooocus outputs symlink, Brave file chooser) can now be meaningfully run against the live system; they remain open until actually verified.
