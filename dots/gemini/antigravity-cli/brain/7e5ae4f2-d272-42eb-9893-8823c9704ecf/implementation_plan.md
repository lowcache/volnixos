# Goal: Rewrite mcp-box CLI into a Highly Portable Go Executable

Rewrite the user-facing `mcp-box` CLI wrapper from Bash into a single, compiled, and highly portable **Go** binary. The Go binary will handle argument parsing, docker environment checks, configuration generation, and OCI image fallback pulling. It will execute the exact same sandboxed `docker run` command with strict isolation parameters, keeping stdio streams (`os.Stdin`/`os.Stdout`/`os.Stderr`) piped directly for latency-free MCP communication. The local Nix flake will be updated to compile this Go binary using `pkgs.buildGoModule`.

---

## User Review Required

> [!IMPORTANT]
> **Dependency-Free Go**: The Go CLI will use exclusively the Go Standard Library (`flag`, `os/exec`, `os`, `path/filepath`, `encoding/json`). This guarantees zero external package dependencies (`vendorHash = null`), compiling instantly and remaining fully reproducible under the Nix sandbox.
> 
> **Binary Name Overlap**: The compiled Go binary will occupy the path `Projects/mcp-box/mcp-box`, replacing the current bash script. The old bash script will be preserved as `Projects/mcp-box/mcp-box.sh` for legacy reference.

---

## Proposed Changes

### Component 1: Go CLI Source Code
Implement the Go CLI with strict parity to the current bash script features.

#### [NEW] [go.mod](file:///home/nondeus/Projects/mcp-box/go.mod)
Initialize a Go module:
```go
module mcp-box
go 1.22
```

#### [NEW] [main.go](file:///home/nondeus/Projects/mcp-box/main.go)
Create the entry point for the CLI:
- **`help`**: Prints comprehensive instructions.
- **`list`**: Lists the pre-packaged MCP servers (`sqlite`, `shell`, `filesystem`, `fetch`).
- **`config <server>`**: Generates Claude-compatible JSON configurations using absolute path resolutions.
- **`build <server>`**: Invokes Nix programmatically to build the OCI image stream and load it:
  `nix build .#<server> --no-link --print-out-paths | xargs -I {} sh -c "{} | docker load"`
- **`run <server> [options] -- [args]`**:
  - Validates Docker daemon availability.
  - Automatically loads the OCI image:
    - If local image is missing and Nix is installed: Triggers the local Nix build.
    - If Nix is absent: Pulls and tags the identical image from `ghcr.io/lowcache`.
  - Parses flags: `-w`/`--workspace`, `-n`/`--network`, `-e`/`--env`.
  - Maps host user UID/GID to container execution to preserve file ownership.
  - Invokes `docker run` with the strict security profiles: `--read-only`, `--tmpfs`, `--cap-drop=ALL`, `--security-opt=no-new-privileges:true`.
  - Pipes `os.Stdin`, `os.Stdout`, and `os.Stderr` directly to ensure zero-latency stdio streaming.

---

### Component 2: Nix Flake Updates
Integrate Go compilation into the declarative flake.

#### [MODIFY] [flake.nix](file:///home/nondeus/Projects/mcp-box/flake.nix)
Update the `mcp-box-cli` package to compile the Go binary:
- Replace `pkgs.writeShellApplication` with `pkgs.buildGoModule`.
- Set `vendorHash = null` for standard library building.
- Set `src = ./.` to fetch local Go sources.

---

### Component 3: Clean up Legacy CLI
#### [MODIFY] [mcp-box.sh](file:///home/nondeus/Projects/mcp-box/mcp-box.sh)
Rename/preserve the old bash script for references.

---

## Verification Plan

### Automated Tests
- Build the Go module locally using Go compiler:
  ```bash
  go build -o mcp-box
  ```
- Build the Go module via the Nix flake:
  ```bash
  nix build .#mcp-box
  ```

### Manual Verification
1. Verify help menus and server listings:
   ```bash
   ./mcp-box list
   ```
2. Verify configuration generation:
   ```bash
   ./mcp-box config sqlite
   ```
3. Test autonomous OCI loading and execution:
   - Temporarily rename `/usr/bin/nix` or check execution when Nix is mocked as absent to verify GHCR pull fallback.
   - Run a sandboxed sqlite or shell query.
4. Verify sandboxing constraints:
   - Test read-only filesystem block: `./mcp-box run shell -- /bin/bash -c "touch /etc/naughty"`
   - Test network isolation block: `./mcp-box run shell -- /bin/bash -c "curl https://google.com"`
