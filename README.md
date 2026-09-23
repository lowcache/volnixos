<div align="center">

<img alt="Volatile NixOS banner" src="./assets/volnixosbanner.png" width="100%">

<p>
  <img alt="NixOS unstable" src="https://img.shields.io/badge/NixOS-unstable-5277C3?style=for-the-badge&logo=nixos&logoColor=white">
  <img alt="Lix" src="https://img.shields.io/badge/Nix_daemon-Lix-3a3a3a?style=for-the-badge&logo=nixos&logoColor=88c0d0">
  <img alt="niri" src="https://img.shields.io/badge/WM-niri-7E9CD8?style=for-the-badge&logoColor=white">
  <img alt="Wayland" src="https://img.shields.io/badge/Display-Wayland-FFB300?style=for-the-badge&logo=wayland&logoColor=white">
</p>
<p>
  <a href="https://wiki.infernalcode.com/"><img alt="Documentation" src="https://img.shields.io/badge/📖_full_docs-volnixos--wiki.infernalcode.com-3e9e40?style=flat-square"></a>
  <a href="https://github.com/lowcache/volnixos/commits/main"><img alt="Last commit" src="https://img.shields.io/github/last-commit/lowcache/volnixos?style=flat-square&logo=git&logoColor=white&label=last%20commit&color=5277C3"></a>
  <a href="https://github.com/lowcache/volnixos/actions/workflows/build.yml"><img alt="Build" src="https://github.com/lowcache/volnixos/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://app.cachix.org/cache/volnixos"><img alt="Binary cache" src="https://img.shields.io/badge/cachix-volnixos-8c62d6?style=flat-square&logo=nixos&logoColor=white"></a>
</p>

### Volatile NixOS — a stateless, flake-driven NixOS workstation

</div>

A declarative, performance-tuned, **ephemeral** NixOS configuration built on Nix Flakes and the
[Lix](https://lix.systems) daemon. The root filesystem is a `tmpfs` wiped on every boot; all durable
state is mapped onto `/persist` via [`impermanence`](https://github.com/nix-community/impermanence). It
adds a CachyOS low-latency kernel, UEFI Secure Boot (Lanzaboote), `sops-nix` secrets, isolated
`microvm.nix` gateways, CUDA-accelerated local AI, and a niri + Noctalia v5 Wayland desktop.

## 📖 Documentation

**Full documentation lives at → [volnixos WIKI](https://wiki.infernalcode.com/)**
**Field Notes, Failures, and the [Volatile Testimony](https://infernalcode.com) in its entirety**


| Topic | |
| :--- | :--- |
| [Architecture](https://wiki.infernalcode.com/architecture/) | Boot, impermanence, kernel, secrets |
| [Networking](https://wiki.infernalcode.com/networking/) | Tor `net-gate` & Tailscale MicroVMs |
| [Desktop](https://wiki.infernalcode.com/desktop/) | niri, Noctalia, theming engine |
| [Reference](https://wiki.infernalcode.com/reference/flake/) | Flake, Home Manager modules, dotfiles |
| [Tooling](https://wiki.infernalcode.com/tooling/makefile/) | Makefile, Fish, agent toolchain |
| [Binary cache & CI](https://wiki.infernalcode.com/tooling/ci-cache/) | The `volnixos` cachix cache and the build that fills it |
| [nix-on-droid](https://wiki.infernalcode.com/nix-on-droid/) | Phone Tier and the nix-on-droid derivation |

## Quick start

```bash
git clone https://github.com/lowcache/volnixos.git ~/.nix-config
cd ~/.nix-config
make check          # nix flake check
make build          # build without switching
sudo make switch    # rebuild + switch (HOST=volnix)
```

> [!NOTE]
> This is my personal, hardware-specific configuration (AMD Ryzen + hybrid AMD/NVIDIA GPU, ASUS
> laptop), published as a **portfolio and reference** — meant to be read and borrowed from, not
> installed wholesale. Treat it as proof-of-work, not a distro.

## Binary cache

Every push to `main` that can change the closure builds the whole system on CI and pushes the
result to [`volnixos.cachix.org`](https://app.cachix.org/cache/volnixos). Hosts pull from it before
any upstream, so `make switch` is a download rather than a rebuild.

The cache earns its keep on the paths nobody else can serve: **NVIDIA built against the CachyOS
kernel**. `nvidia-x11`/`nvidia-open` are `unfreeRedistributable`, so Hydra never builds them for
anyone, and they are additionally bound to the exact kernel version. That store path exists only
where someone publishes it.

```nix
nix.settings = {
  substituters       = [ "https://volnixos.cachix.org" ];
  trusted-public-keys = [ "volnixos.cachix.org-1:GUKpgN2Tzh67uYZtUaEsFr1U7UVLrFG1iCoF860CY5Y=" ];
};
```

The kernel itself comes from the [lantian attic](https://attic.xuyh0120.win/lantian), not from this
cache; CI asserts it is a cache hit before building, because a source build of it does not fit in a
GitHub Actions job. Details, including the `NIX_CONFIG` ordering trap that made the substituters
silently disappear, are in
[Binary Cache & CI](https://wiki.infernalcode.com/tooling/ci-cache/).

> [!TIP]
> Push before you switch. `make comm && make push` → `gh run watch` → `make switch`. Switching first
> just means building locally and then having CI rebuild the same paths.

## Layout

```text
.nix-config/
├── flake.nix          # inputs, overlays, host (volnix), VM runners
├── Makefile           # canonical operations interface (make help)
├── .github/workflows/ # CI: builds the closure, pushes to cachix:volnixos
├── nixos/             # system & Hardware Modules
├── home/              # Home Manager modules
├── droid/             # Phone-Agent and nix-on-droid modules
├── overrides/         # Overrides & Patches
├── dots/              # dotfiles (out-of-store symlinked to ~/.config)
├── scripts/           # agent toolchain (agent-scaffold, helpers)
└── assets/            # banner / branding
```

<div align="center">
<img alt="ai note" src="./assets/ai_note.png" width="100%"">
</div>

