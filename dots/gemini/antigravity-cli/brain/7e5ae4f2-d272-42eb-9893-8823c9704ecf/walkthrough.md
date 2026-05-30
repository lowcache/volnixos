# Walkthrough: Migrating mcp-box CLI from Bash to Go

We have successfully migrated the **`mcp-box`** user-facing CLI wrapper from a Bash script to a compiled, highly portable **Go** binary. The Go CLI utilizes exclusively the Go Standard Library (`flag`, `os/exec`, `os`, `path/filepath`, `encoding/json`), ensuring zero external package dependencies (`vendorHash = null`) and completely clean, deterministic compilation under the Nix sandbox.

---

## 1. Summary of Changes

All modified and newly created components are located in [mcp-box](file:///home/nondeus/Projects/mcp-box/):

1. **`go.mod`**: Initializes the `mcp-box` module path for Go compilation.
2. **`main.go`**: The complete, dependency-free Go CLI implementation providing:
   - **`list`**: Lists pre-packaged MCP servers.
   - **`config <server>`**: Generates Claude-compatible JSON configurations using dynamic absolute path resolutions.
   - **`build <server>`**: Programmatically builds the OCI image stream via Nix and loads it into Docker:
     `nix build .#<server> --no-link --print-out-paths | docker load`
   - **`run <server> [options] -- [args]`**:
     - Automatically checks if the OCI image is loaded locally.
     - Performs **Nix Autonomy Fallback**: Detects if Nix is present. If so, builds the image locally. If not, pulls and tags it from the registry `ghcr.io/lowcache`.
     - Parses custom flags manually (`-w`/`--workspace`, `-n`/`--network`, `-e`/`--env`) and preserves trailing server arguments post-`--`.
     - Spawns the Docker container utilizing strict sandboxing parameters: `--read-only`, `--tmpfs`, `--cap-drop=ALL`, `--security-opt=no-new-privileges:true`.
     - Maps `os.Stdin`, `os.Stdout`, and `os.Stderr` directly to ensure zero-latency stdio streaming for Model Context Protocol communication.
3. **`flake.nix`**: Refactored the `mcp-box-cli` package to compile the Go binary using Nix's `pkgs.buildGoModule` instead of `pkgs.writeShellApplication`.
4. **`mcp-box.sh`**: Preserved the legacy Bash script for historic reference.

---

## 2. Compilation Results

We verified that the Go module compiles hermetically inside the Nix store:

*   **Nix Build Command**:
    ```bash
    nix build .#mcp-box --no-link --print-out-paths
    ```
*   **Result**: Success!
    ```
    warning: Git tree '/home/nondeus/Projects/mcp-box' is dirty
    /nix/store/y2ianm92z389pcrrmidh942j2437q0s4-mcp-box-1.0.0
    ```
    The compiled binary is successfully generated and stored at `/nix/store/y2ianm92z389pcrrmidh942j2437q0s4-mcp-box-1.0.0/bin/mcp-box`.

---

## 3. Placement & Execution Guide

To place the compiled executable directly in your local directory for direct use, please run the following command from your terminal:

```bash
# Create local symlink to the Nix-compiled Go binary:
ln -sf /nix/store/y2ianm92z389pcrrmidh942j2437q0s4-mcp-box-1.0.0/bin/mcp-box ./mcp-box
```

Alternatively, you can compile it directly using the Go compiler:
```bash
go build -o mcp-box
```

Once the binary is placed, you can run all standard operations identically:
```bash
# List pre-packaged sandboxes
./mcp-box list

# Generate Claude integration config
./mcp-box config sqlite

# Run sandboxed shell
./mcp-box run shell --workspace /tmp/test-workspace -- /bin/bash -c "touch /etc/naughty"
```
