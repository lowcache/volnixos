# Known Mistakes and Prevention Rules (`memory/mistakes.md`)

This file catalogs past bugs, configuration issues, and operational pitfalls encountered on **Infernal NixOS**. AI agents must study these cases to prevent regression.

---

## 1. NixOS Rebuild Switched Graphical Session Logout & Process Termination

* **Incident (2026-06-01):** Running `sudo nixos-rebuild switch` from a terminal window (`kitty`) inside the graphical session (Hyprland) caused the graphical display manager (`greetd`) to restart due to package updates. 
* **The Bug:** The restart of `greetd` automatically logged the user out, closing all X11/Wayland clients, which instantly killed the parent terminal emulator process (`kitty`). This aborted the `nixos-rebuild switch` process mid-execution. 
* **Impact:** Services (such as `open-webui` and `ollama`) had already been stopped during the update transition but were left inactive (dead) because the switch process was killed before reaching their restart step.
* **Prevention Rule:** When major graphical system configurations, library dependencies (`glibc`), or session managers are changed, always warn the human developer before executing a switch. Recommend executing the switch via a systemd background task, systemd-run, or multiplexer (`tmux`/`screen`) to isolate the rebuild process from session terminations.

---

## 2. ASUS Shutdown Service Systemd Block

* **Incident (2026-06-01):** The `nixos-rebuild switch` process timed out and aborted (exit status `101`) during system activation because the `asus-shutdown.service` hung during its deactivation phase.
* **The Bug:** The systemd unit for `asus-shutdown.service` is configured with `SendSIGKILL=no`. When systemd attempts to stop the service, it sends a `SIGTERM` signal. The `asusctl` shutdown daemon intercepts `SIGTERM` and defers exit indefinitely waiting for safe system boundaries. Since systemd is prevented from sending `SIGKILL` to force-terminate it, the unit hangs forever until the systemd stop timeout is exceeded, failing the overall switch activation.
* **Impact:** Interrupted system builds, leaving other services (like `NetworkManager`) stopped and un-restored on boot.
* **Prevention Rule:** If `asus-shutdown` hangs, manually force-kill the untracked stale background daemon process (e.g., `sudo kill -9 <PID>`) and then start the new systemd unit to restore tracking.

---

## 3. Ollama Hybrid Nvidia GPU Battery Drain

* **Incident (2026-06-01):** The laptop experienced exceptionally high idle power draw and rapid battery depletion.
* **The Bug:** `pkgs.ollama-cuda` ran as a system boot service. Even when idle, it initialized the GPU drivers and held open descriptors on `/dev/nvidia*`. This blocked the Nvidia GPU from entering its runtime power suspend state (RTD3, 0W draw), forcing it to stay active at 42W power usage.
* **Prevention Rule:** Always ensure Ollama is configured with `"OLLAMA_KEEP_ALIVE=5m"` (or shorter) in its service environment variables. This forces Ollama to unload models and release all active CUDA handles to the discrete GPU after a period of inactivity, letting the driver power off the card completely.

---

## 4. Fooocus Symlink Path and Folder Name Typos

* **Incident (2026-06-01):** The out-of-store symlink mapping for Fooocus outputs resolved to a broken target path, preventing user access to generated images.
* **The Bug:** The directory name in `home/persist.nix` contained a typographical error (`ai-generatiobn` with an extra 'b') while the actual directory created in `nixos/configuration.nix` was named `/home/lowcache/Storage/ai-generation`. Additionally, the symlink key itself contained a spelling mismatch (`ouputs` instead of `outputs`).
* **Prevention Rule:** Double-check directory declarations against `/persist` boundaries. Ensure Home Manager out-of-store paths and NixOS system tmpfiles rules utilize identical spelling profiles.

---

## 5. Shell Function/Alias Syntax Errors in `home/shell.nix`

* **Incident (2026-06-01):** Audit found three silent defects in the fish config that never error at build time but fail at runtime.
* **The Bugs:**
  * `setwall`: `ln - sf "$img" ...` — the space split `-` and `sf` into separate args, so the symlink update always failed.
  * `clear` alias: `printf '033[...'` — the octal ESC was missing its backslash, so it printed literal `033[...` instead of clearing. Note: Nix double-quoted strings eat a lone backslash, so the fix must be `\\033` to emit `\033` to fish.
  * `forggo`/`forgstp` aliases targeted `docker-forge.service`, which is not declared (only the `fooocus` oci-container exists). Commented out pending a forge container.
* **Prevention Rule:** Shell strings embedded in Nix are not validated by `nix flake check` — they only fail when invoked. When editing `home/shell.nix`, mentally run each alias/function, and remember to double-escape backslashes (`\\`) for any escape sequence that must survive into the shell.
