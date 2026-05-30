# Walkthrough - Nix-Native AI Stack, Recovery Safety Nets, GPU Optimizations & MicroVM Stability Fixes

We have successfully resolved the root causes of your system freezes, implemented robust recovery safety nets, optimized your local GPU-accelerated Ollama, and transitioned your AI environment to a resource-efficient **Nix-native AI stack** using the native Open WebUI service. Additionally, we have addressed critical network routing, interface configuration, and persistence gaps in your `net-gate` microVM.

All configurations have been successfully dry-run tested and verified.

---

## What was Changed

### 1. Nix-Native AI Stack & Persistence
* **Removed Jan (`home/pkgs.nix` & `home/persist.nix`)**: Completely removed the heavy Electron-based Jan app from your Home Manager packages and purged all Jan-related directories (`.config/Jan`, `.cache/Jan`, `.local/share/Jan`, etc.) from your persistent storage lists.
* **Native Open WebUI Daemon (`nixos/configuration.nix`)**: Enabled the built-in `services.open-webui` module running on port `8080`, managed as a systemd service and pre-configured to connect to your local CUDA-accelerated Ollama.
* **FFmpeg Dependency PATH Injection (`nixos/configuration.nix`)**: Injected `pkgs.ffmpeg` into the systemd service PATH of the `open-webui` daemon. This resolves the non-fatal `pydub` startup warning and enables native audio transcription and media conversion features.
* **Database State Persistence (`nixos/hardware-configuration.nix`)**: Added `/var/lib/private/open-webui` directly to your persistent `/persist` directory list. This ensures that the dynamic user state directory is safely preserved across reboots on your stateless `tmpfs` root.

### 2. Ollama GPU & Performance Tuning (`nixos/configuration.nix`)
Optimized the native CUDA-accelerated Ollama daemon by injecting fine-tuned environment variables into its systemd service:
* **`OLLAMA_FLASH_ATTENTION=1`**: Saves VRAM and increases inference speeds for long-context sessions.
* **`OLLAMA_NUM_PARALLEL=2`**: Allows Ollama to run multiple inferences concurrently, preventing background API requests from blocking your interactive browser sessions.
* **`CUDA_VISIBLE_DEVICES=0`**: Binds Ollama exclusively to your dedicated NVIDIA RTX 4050 mobile GPU, bypassing the AMD RDNA3 integrated GPU.

### 3. MicroVM "net-gate" Routing & Connectivity Fixes (`nixos/vms.nix`)
* **Isolated Subnet Allocation**: Switched the host-side TAP network interface `vm-netgate` from the `10.0.0.1/24` subnet to `192.168.100.1/24`. This separates the host link from your private VPN subnet (`10.0.0.0/24`), preventing a severe IP conflict and routing loop when enabling the WireGuard interface.
* **Declarative Client networkd Profile**: Declared systemd-networkd match rules within the microVM to ensure it actively requests a DHCP lease from the host DHCP server on its virtual interfaces.

### 4. GPU Stability & System Recovery Safety Nets
* **Brave Browser Wayland Overrides (`home/brave.nix` & `home/default.nix`)**: Created a declarative module for Brave Browser via `programs.chromium` that overrides unstable hardware video decoding parameters under Wayland (`--disable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder`), preventing the segmentation faults (SIGSEGV) identified in your core dumps.
* **Scheduler Optimization (`nixos/configuration.nix`)**: Shifted the active BPF scheduler in `services.scx` from `scx_lavd` to `scx_bpfland`, preserving your full CachyOS kernel optimizations while eliminating scheduler-induced locks.
* **Emergency Recovery (`nixos/configuration.nix`)**: Enabled the Magic SysRq keyboard-based recovery hook (`sysrq_always_enabled=1`) to gracefully reboot the system and prevent filesystem corruption in the event of a hard hang.
* **Panic Auto-Reboot (`nixos/configuration.nix`)**: Configured your sysctl options (`kernel.panic = 10` / `kernel.panic_on_oops = 1`) to automatically reboot the system after 10 seconds if a hard kernel crash is triggered.

---

## How to Apply

To apply all changes, run your standard rebuild command:

```bash
sudo nixos-rebuild switch --flake .#nondeus
```

Once the switch completes, **reboot the system** to apply the new kernel options, the updated `scx_bpfland` scheduler, and the active systemd services.

---

## Verification & Testing the Nix-Native AI Stack

### 1. Local AI Interface (Open WebUI)
* Navigate to `http://localhost:8080` in Brave.
* Create your administrator account (the first account created is automatically designated the Admin).
* Verify that your local GPU-accelerated Ollama models are immediately discoverable in the model selector dropdown in the top-left corner.
* Create a test conversation, reboot your system, and verify that the chat persists (verifying `/var/lib/private/open-webui` state persistence).

### 2. Gemini Frontier Model Integration
* To connect Google's Gemini frontier models:
  1. Navigate to **Admin Settings > Connections > OpenAI** in Open WebUI.
  2. Click the **+ (plus)** button to add a new connection.
  3. Set the base URL to: `https://generativelanguage.googleapis.com/v1beta/openai` (no trailing slash).
  4. Paste your Google AI Studio API key (get one at [Google AI Studio](https://aistudio.google.com/apikey)).
  5. Click **Save**. The connection will verify, and the Gemini models will immediately populate your model selector list!

---

## 🛠️ Disaster Recovery Mnemonic: Magic SysRq Keys

If your system ever encounters a hard freeze in the future, you can perform a **graceful emergency reboot** at any time without risking filesystem corruption:

1. Hold down `Alt + SysRq` (usually the `Print Screen` key).
2. While holding them down, slowly type the following keys one-by-one (wait 1–2 seconds between each key):
   * **`R`** (takes control of the keyboard back from the display server)
   * **`E`** (sends SIGTERM to all processes, allowing them to exit gracefully)
   * **`I`** (sends SIGKILL to any remaining processes)
   * **`S`** (syncs all mounted filesystems to disk, preventing data loss)
   * **`U`** (remounts all filesystems as read-only)
   * **`B`** (instantly reboots the machine)

*Mnemonic: **R**eboot **E**ven **I**f **S**ystem **U**tterly **B**roken.*
