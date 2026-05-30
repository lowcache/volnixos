# NixOS Boot Optimization & GPU Stability Analysis

Analyze the root cause of the 60-second boot delay and the performance implications of the GPU stability configurations, and implement a fix for the boot delay.

## GPU Stability & Performance Analysis

Here is a detailed breakdown of the settings toggled during troubleshooting, their role in resolving the freezes, and their performance/power implications:

### 1. CPU C-States Restriction (`processor.max_cstate=1`)
*   **What it does:** Restricts the CPU from entering deep sleep states. `cstate=1` restricts the processor to C0 (fully active) and C1 (light sleep), completely disabling deep power-saving states like C6.
*   **Why it fixed the issue:** Random idle freezing is a well-documented hardware behavior on AMD Ryzen platforms (often called "Ryzen idle freeze"). It is caused by transient voltage drops when the CPU core transitions back from deep sleep states. Setting `max_cstate=1` prevents the core voltage from dropping below stable levels.
*   **Performance Hit:** **None.** It actually *improves* CPU latency/responsiveness slightly by eliminating wake-up latencies from deep sleep.
*   **Power/Battery Impact:** **Significant.** It prevents the CPU from entering ultra-low power states when idle, which will increase power consumption, idle temperatures, fan speeds, and substantially reduce battery life (highly critical on laptops).
*   **Recommendations:**
    *   **Keep it for now** to maintain absolute stability since you have verified a 24-hour continuous run without issues.
    *   **To toggle back/test:** You can try increasing it to `processor.max_cstate=5` (which allows moderate sleep states but avoids the deepest ones), or check your motherboard/laptop BIOS for a setting named **"Power Supply Idle Control"** and set it to **"Typical Current Idle"**. This keeps idle voltage slightly higher without completely disabling sleep states.

### 2. Open-Source NVIDIA Kernel Modules (`hardware.nvidia.open = true`)
*   **What it does:** Switches the kernel-space portion of the NVIDIA driver from the proprietary binary blob to NVIDIA's official open-source kernel modules.
*   **Why it fixed the issue:** The open driver integrates far better with modern Linux kernels (like CachyOS) and modern Wayland compositors (Hyprland). It avoids many legacy lockups, synchronization issues, and memory leaks present in the closed driver.
*   **Performance Hit:** **Zero (0%).** For Turing architectures and newer (RTX 20-series through RTX 40-series, like your RTX 4050 Mobile), the open-source kernel modules offer identical performance, full Vulkan/CUDA support, and GSP (GPU System Processor) firmware execution.
*   **Recommendations:** **Keep it.** There is no performance hit, and it is the modern standard for NVIDIA on Wayland/NixOS.

### 3. Disabling Sched-ext (`services.scx.enable = false`)
*   **What it does:** Disables extensible BPF schedulers (like `scx_bpfland`) and falls back to the default kernel scheduler.
*   **Why it fixed the issue:** While BPF schedulers can improve desktop responsiveness under load, they are highly experimental and known to cause kernel instability, scheduling stalls, and GPU driver lockups under intensive workloads (such as local AI inference or gaming).
*   **Performance Hit:** **Minimal to None.** The CachyOS kernel contains a highly tuned default scheduler (EEVDF/BORE). Returning to it ensures robust thread scheduling under AI workloads without experimental BPF overhead.
*   **Recommendations:** **Keep it disabled.** Standard kernel schedulers are much more robust and stable for mixed workloads.

---

## Boot Time Analysis & Fix

### Root Cause of the 60-Second Delay
From the systemd journal logs, the bottleneck is the **`microvm@net-gate`** service:
1. `microvm@net-gate` is an autostart service representing a virtual machine.
2. The module configures this service as `Type=notify` (because a vsock CID is set). Under this type, systemd on the host blocks the boot sequence and waits for the guest VM to boot up and send a readiness notification via vsock.
3. The guest VM takes approximately **36 seconds** to fully boot and reach `multi-user.target` before it sends the notification.
4. During this entire time, systemd on the host refuses to reach `multi-user.target` or `graphical.target`.
5. The Universal Wayland Session Manager (`uwsm`), which is started by `greetd/tuigreet` upon login, sees that `graphical.target` is not yet active and pauses the startup of Hyprland, waiting for up to 60 seconds.

### Proposed Solution
We can override the systemd service type of the MicroVM on the host side to `simple`.
By setting `Type = "simple"`, systemd will launch the virtual machine process and immediately mark the service as active. The host will instantly proceed to reach `graphical.target` and start Hyprland without waiting for the guest VM to finish booting. The guest VM will continue booting in the background.

## User Review Required

> [!NOTE]
> Modifying the MicroVM service type to `simple` decouples the VM's internal boot time from the host's graphical startup. The VM will boot in the background, meaning network routing/services managed inside the VM might not be immediately available in the first few seconds after reaching the desktop.

## Proposed Changes

### MicroVM Host Configuration

#### [MODIFY] [vms.nix](file:///home/nondeus/.nix-config/nixos/vms.nix)
Force `systemd.services."microvm@net-gate".serviceConfig.Type` to `simple` to prevent it from blocking host startup.

```diff
  # Host-side overrides for fast shutdown
  systemd.services."microvm@net-gate".serviceConfig.TimeoutStopSec = "10s";
+ systemd.services."microvm@net-gate".serviceConfig.Type = lib.mkForce "simple";
  systemd.services."microvm-virtiofsd@net-gate".serviceConfig.TimeoutStopSec = "5s";
```

---

## Verification Plan

### Automated Tests
*   Run `nix-instantiate` or a syntax check on the Nix configuration to verify that the change is syntactically correct and evaluates without errors:
    ```bash
    nix-instantiate --parse /home/nondeus/.nix-config/nixos/vms.nix
    ```

### Manual Verification
*   The user will rebuild the system configuration and reboot to verify that the 60-second graphical target queue is eliminated.
