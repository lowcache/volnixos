#!/usr/bin/env fish
# migrate-vscodium-to-antigravity.fish
#
# Run this AFTER nixos-rebuild switch has applied the persist.nix changes.
# The Antigravity directories must already be bind-mounted from /persist
# or the copied files will be lost on next boot.
#
# Usage:
#   chmod +x migrate-vscodium-to-antigravity.fish
#   ./migrate-vscodium-to-antigravity.fish

set VSCODIUM_CONFIG "$HOME/.config/VSCodium"
set ANTIGRAVITY_CONFIG "$HOME/.config/Antigravity IDE"
set VSCODIUM_EXTENSIONS "$HOME/.vscode-oss/extensions"
set ANTIGRAVITY_CLI antigravity-ide

function info
    set_color green
    printf '[✓] '
    set_color normal
    echo $argv
end

function warn
    set_color yellow
    printf '[!] '
    set_color normal
    echo $argv
end

function err
    set_color red
    printf '[✗] '
    set_color normal
    echo $argv
end

# ------------------------------------------------------------------
# Pre-flight: verify persistence is active
# ------------------------------------------------------------------
function check_persistence
    set -l failed 0
    set -l user (basename $HOME)

    for dir in "$HOME/.antigravity" "$HOME/.antigravity-ide" "$ANTIGRAVITY_CONFIG"
        set -l relpath (string replace "$HOME/" "" -- $dir)
        set -l persist_path "/persist/home/$user/$relpath"

        if not test -d $persist_path
            err "Persistence not active for $dir"
            err "Expected $persist_path to exist."
            set failed 1
        end
    end

    if test $failed -eq 1
        echo
        err "Persistence directories are not mounted."
        err "Run: sudo nixos-rebuild switch --flake ~/.nix-config"
        err "Then re-run this script."
        return 1
    end

    info "Persistence directories verified"
end

# ------------------------------------------------------------------
# Step 1: Copy settings.json
# ------------------------------------------------------------------
function copy_settings
    set -l src "$VSCODIUM_CONFIG/User/settings.json"
    set -l dst "$ANTIGRAVITY_CONFIG/User/settings.json"

    if not test -f $src
        warn "No VSCodium settings.json found at $src — skipping"
        return
    end

    mkdir -p "$ANTIGRAVITY_CONFIG/User"
    cp $src $dst
    info "Copied settings.json"
end

# ------------------------------------------------------------------
# Step 2: Copy keybindings.json (if exists)
# ------------------------------------------------------------------
function copy_keybindings
    set -l src "$VSCODIUM_CONFIG/User/keybindings.json"
    set -l dst "$ANTIGRAVITY_CONFIG/User/keybindings.json"

    if not test -f $src
        warn "No keybindings.json found — skipping"
        return
    end

    cp $src $dst
    info "Copied keybindings.json"
end

# ------------------------------------------------------------------
# Step 3: Copy snippets
# ------------------------------------------------------------------
function copy_snippets
    set -l src "$VSCODIUM_CONFIG/User/snippets"
    set -l dst "$ANTIGRAVITY_CONFIG/User/snippets"

    if not test -d $src; or test (count (command ls $src 2>/dev/null)) -eq 0
        warn "No snippets found — skipping"
        return
    end

    mkdir -p $dst
    cp -r $src/* $dst/
    info "Copied snippets"
end

# ------------------------------------------------------------------
# Step 4: Install extensions
# ------------------------------------------------------------------
function install_extensions
    if not command -q $ANTIGRAVITY_CLI
        err "$ANTIGRAVITY_CLI not found in PATH"
        err "Cannot install extensions automatically."
        return 1
    end

    # Collect VSCodium extension IDs
    set -l vscodium_exts
    if test -d $VSCODIUM_EXTENSIONS
        for entry in (command ls $VSCODIUM_EXTENSIONS)
            test $entry = "extensions.json"; and continue
            # Strip version suffix: publisher.name-1.2.3-universal -> publisher.name
            set -l id (string replace -r -- '-[0-9][0-9]*\.[0-9].*' '' $entry)
            set -a vscodium_exts $id
        end
    end

    if test (count $vscodium_exts) -eq 0
        warn "No VSCodium extensions found to migrate"
        return
    end

    # Collect already-installed Antigravity extensions
    set -l installed
    set -l antigravity_ext_dir "$HOME/.antigravity/extensions"
    if test -d $antigravity_ext_dir
        for entry in (command ls $antigravity_ext_dir)
            test $entry = "extensions.json"; and continue
            set -l id (string replace -r -- '-[0-9][0-9]*\.[0-9].*' '' $entry)
            set -a installed $id
        end
    end

    # Deduplicate and diff
    set -l unique_exts (printf '%s\n' $vscodium_exts | sort -u)
    set -l to_install
    for ext in $unique_exts
        if not contains -- $ext $installed
            set -a to_install $ext
        end
    end

    if test (count $to_install) -eq 0
        info "All VSCodium extensions are already installed in Antigravity IDE"
        return
    end

    info "Installing "(count $to_install)" extensions into Antigravity IDE..."
    set -l fail_count 0
    for ext in $to_install
        printf '  → %s ... ' $ext
        if $ANTIGRAVITY_CLI --install-extension $ext --force &>/dev/null
            set_color green
            echo ok
            set_color normal
        else
            set_color yellow
            echo failed
            set_color normal
            set fail_count (math $fail_count + 1)
        end
    end

    if test $fail_count -gt 0
        warn "$fail_count extension(s) failed to install."
        warn "Try downloading .vsix files from https://open-vsx.org and installing with:"
        warn "  $ANTIGRAVITY_CLI --install-extension ./file.vsix"
    else
        info "All extensions installed"
    end
end

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
echo
echo "=== VSCodium → Antigravity IDE Migration ==="
echo

check_persistence; or exit 1
copy_settings
copy_keybindings
copy_snippets
install_extensions

echo
info "Migration complete. Restart Antigravity IDE to apply changes."
