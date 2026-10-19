# gd — Google Drive from the terminal (rclone underneath). `gd help` for usage.
# Drive paths are relative to the Drive root; cp-style: with 2+ args the last one is the destination.
cfg=${XDG_CONFIG_HOME:-$HOME/.config}/gd/config
# shellcheck source=/dev/null
[ -f "$cfg" ] && . "$cfg"
GD_REMOTE=${GD_REMOTE:-gdrive}
GD_MOUNT=${GD_MOUNT:-$HOME/gdrive}
GD_SYNC_LOCAL=${GD_SYNC_LOCAL:-$HOME/Drive}
GD_SYNC_REMOTE=${GD_SYNC_REMOTE:-}
GD_BACKUP_DIR=${GD_BACKUP_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/gd/backup}

die() { echo "gd: $*" >&2; exit 1; }
r() { printf '%s:%s' "$GD_REMOTE" "${1#/}"; }
progress=()
[ -t 1 ] && progress=(-P)

need_remote() {
  rclone listremotes | grep -qxF "$GD_REMOTE:" || die "no rclone remote '$GD_REMOTE'; run: gd setup"
}

is_dir() { [ "$(rclone lsjson --stat "$(r "$1")" | jq -r .IsDir)" = true ]; }

confirm() {
  local ok
  read -rp "$1 [y/N] " ok
  [[ $ok == [yY]* ]] || die aborted
}

usage() {
  cat <<EOF
gd — Google Drive from the terminal (remote: $GD_REMOTE)

  setup                       one-time OAuth; creates rclone remote '$GD_REMOTE'
  ls [path]                   list a folder (dirs end in /)
  tree [path]                 folder tree
  find <glob> [path]          recursive name search, e.g. gd find '*.pdf'
  push <local>... [dir]       upload files/dirs into Drive dir (default: root)
  pull <path>... [localdir]   download files/dirs into localdir (default: .)
  pick [path]                 fzf multi-select from Drive, pull into .
  cat <path>                  stream a file to stdout
  put <path>                  stream stdin into a Drive file
  mkdir <path>                create a folder
  mv <src> <dst>              move/rename within Drive
  rm <path>...                delete (goes to Drive trash)
  link <path>                 print a shareable link
  sync up|down                one-way mirror $GD_SYNC_LOCAL <-> $(r "$GD_SYNC_REMOTE") (preview + confirm)
  bisync [--resync]           two-way sync of the same pair; first run needs --resync
  mount [dir] / umount [dir]  FUSE mount (default $GD_MOUNT)
  about                       quota / usage
  rclone <args>...            raw rclone passthrough

Config: env or $cfg (shell syntax): GD_REMOTE GD_MOUNT GD_SYNC_LOCAL GD_SYNC_REMOTE GD_BACKUP_DIR.
Extra rclone flags via its env, e.g. RCLONE_DRY_RUN=true gd push big/
EOF
}

setup() {
  if rclone listremotes | grep -qxF "$GD_REMOTE:"; then
    echo "remote '$GD_REMOTE' exists; reconnect with: gd rclone config reconnect $GD_REMOTE:"
    return
  fi
  local args=(scope=drive)
  # Own OAuth client avoids rclone's shared, heavily rate-limited one.
  [ -n "${GD_CLIENT_ID:-}" ] && args+=(client_id="$GD_CLIENT_ID" client_secret="${GD_CLIENT_SECRET:-}")
  rclone config create "$GD_REMOTE" drive "${args[@]}"
  echo "done. The token sits in plaintext in $(rclone config file | tail -1);"
  echo "encrypt it with: gd rclone config  (s → set configuration password)"
}

push() {
  [ $# -ge 1 ] || die "push <local>... [dir]"
  local dest=
  [ $# -ge 2 ] && { dest=${*: -1}; dest=${dest%/}; set -- "${@:1:$#-1}"; }
  local src
  for src in "$@"; do
    [ -e "$src" ] || die "no such local path: $src"
    if [ -d "$src" ]; then
      rclone copy "${progress[@]}" "$src" "$(r "$dest/$(basename "$(realpath "$src")")")"
    else
      rclone copy "${progress[@]}" "$src" "$(r "$dest")"
    fi
  done
}

pull() {
  [ $# -ge 1 ] || die "pull <path>... [localdir]"
  local dest=.
  [ $# -ge 2 ] && { dest=${*: -1}; set -- "${@:1:$#-1}"; }
  local src
  for src in "$@"; do
    if is_dir "$src"; then
      rclone copy "${progress[@]}" "$(r "$src")" "$dest/$(basename "$src")"
    else
      rclone copy "${progress[@]}" "$(r "$src")" "$dest"
    fi
  done
}

pick() {
  local base=${1:-}
  base=${base#/}
  local picked=()
  mapfile -t picked < <(rclone lsf -R --files-only "$(r "$base")" | fzf -m --prompt "$GD_REMOTE:$base> ")
  [ ${#picked[@]} -gt 0 ] || exit 0
  local f
  for f in "${picked[@]}"; do pull "${base:+$base/}$f" .; done
}

rm_() {
  [ $# -ge 1 ] || die "rm <path>..."
  local p
  for p in "$@"; do
    if is_dir "$p"; then
      confirm "delete folder $(r "$p") and everything in it?"
      rclone purge "$(r "$p")"
    else
      rclone deletefile "$(r "$p")"
    fi
  done
}

sync_() {
  local src dst backup=()
  case ${1:-} in
    up) src=$GD_SYNC_LOCAL dst=$(r "$GD_SYNC_REMOTE") ;;
    # Local files the mirror would delete or overwrite are kept, not lost.
    down)
      src=$(r "$GD_SYNC_REMOTE") dst=$GD_SYNC_LOCAL
      backup=(--backup-dir "$GD_BACKUP_DIR/$(date +%Y%m%dT%H%M%S)")
      ;;
    *) die "sync up|down" ;;
  esac
  mkdir -p "$GD_SYNC_LOCAL"
  rclone sync --dry-run "$src" "$dst" 2>&1 | grep -E 'as --dry-run is set|ERROR' || { echo "already in sync"; return; }
  confirm "apply: $src -> $dst?"
  rclone sync "${progress[@]}" "${backup[@]}" "$src" "$dst"
}

bisync() {
  mkdir -p "$GD_SYNC_LOCAL"
  rclone bisync "$GD_SYNC_LOCAL" "$(r "$GD_SYNC_REMOTE")" \
    --create-empty-src-dirs --compare size,modtime,checksum --resilient --recover "$@"
}

mount_() {
  local dir=${1:-$GD_MOUNT}
  mkdir -p "$dir"
  rclone mount "$GD_REMOTE:" "$dir" --vfs-cache-mode full --daemon
  echo "mounted $GD_REMOTE: at $dir (gd umount to detach)"
}

cmd=${1:-help}
shift || true
case $cmd in
  help | -h | --help) usage; exit 0 ;;
  setup) setup; exit 0 ;;
  rclone) exec rclone "$@" ;;
  umount) fusermount3 -u "${1:-$GD_MOUNT}" 2>/dev/null || fusermount -u "${1:-$GD_MOUNT}"; exit 0 ;;
esac
need_remote
case $cmd in
  ls) rclone lsf "$(r "${1:-}")" ;;
  tree) rclone tree "$(r "${1:-}")" ;;
  find)
    [ $# -ge 1 ] || die "find <glob> [path]"
    rclone lsf -R --include "$1" --ignore-case "$(r "${2:-}")"
    ;;
  push) push "$@" ;;
  pull) pull "$@" ;;
  pick) pick "$@" ;;
  cat) [ $# -ge 1 ] || die "cat <path>"; rclone cat "$(r "$1")" ;;
  put) [ $# -ge 1 ] || die "put <path>"; rclone rcat "$(r "$1")" ;;
  mkdir) [ $# -ge 1 ] || die "mkdir <path>"; rclone mkdir "$(r "$1")" ;;
  mv) [ $# -eq 2 ] || die "mv <src> <dst>"; rclone moveto "$(r "$1")" "$(r "$2")" ;;
  rm) rm_ "$@" ;;
  link) [ $# -ge 1 ] || die "link <path>"; rclone link "$(r "$1")" ;;
  sync) sync_ "$@" ;;
  bisync) bisync "$@" ;;
  mount) mount_ "$@" ;;
  about) rclone about "$GD_REMOTE:" ;;
  *) usage >&2; exit 64 ;;
esac
