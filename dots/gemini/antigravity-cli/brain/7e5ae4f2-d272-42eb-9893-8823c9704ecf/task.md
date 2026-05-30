# Checklist: Migrating mcp-box CLI from Bash to Go

- [x] Preserve legacy Bash script as `mcp-box.sh`
- [x] Create `go.mod` file to initialize the Go module
- [x] Implement `main.go` in Go Standard Library for argument parsing, checks, registry pulls, and subprocess execution
- [x] Modify `flake.nix` to use `pkgs.buildGoModule` for hermetic Go compilation
- [x] Verify and test the Go CLI implementation
  - [x] Verify local Go compilation (`go build`)
  - [x] Verify hermetic Nix flake compilation (`nix build`)
  - [x] Test standard commands (`list`, `config`, `build`, `run`)
  - [x] Test image checks and fallback pull behaviour (Nix vs registry pulls)
  - [x] Test container sandbox security boundaries (read-only rootfs, network profiles, UID/GID mapping)
- [x] Create `walkthrough.md` to document the completed migration and test results
