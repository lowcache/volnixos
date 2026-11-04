# wiki-sync: apply pending docs/wikifixins notes to the wiki, build, deploy.
# A fixin is pending until its "<sha256>  <name>" line is in the wiki's
# committed ledger, so edits to an applied fixin make it pending again.
# Env (set by home/wiki-sync.nix): WIKI_DIR, FIXINS_DIR, NIXCFG_DIR.

LEDGER=.wikifixins-applied
QUIET=${WIKI_SYNC_QUIET:-90}
WORK=${WIKI_SYNC_WORK:-$HOME/Storage/tmp/wiki-sync}
MODEL=${WIKI_SYNC_MODEL:-sonnet}

log() { printf 'wiki-sync: %s\n' "$*" >&2; }
notify() { notify-send -a wiki-sync -u "$1" "$2" "$3" 2>/dev/null || true; }
die() {
  log "$1"
  notify critical "wiki-sync failed" "$1"
  exit 1
}

fixins() {
  find "$FIXINS_DIR" -maxdepth 1 -type f -name '*.md' ! -name CLAUDE.md -printf '%f\n' | sort
}

# Ledger as committed on main, not the working tree: only shipped work counts.
ledger() { git -C "$WIKI_DIR" show "main:$LEDGER" 2>/dev/null || true; }

key() { printf '%s  %s\n' "$(sha256sum <"$FIXINS_DIR/$1" | cut -d' ' -f1)" "$1"; }

pending() {
  local l f
  l=$(ledger)
  while read -r f; do
    [ -n "$f" ] || continue
    grep -qxF "$(key "$f")" <<<"$l" || printf '%s\n' "$f"
  done < <(fixins)
}

# Fixins get written and then edited; wait until the folder has been still.
quiesce() {
  local newest age
  while :; do
    newest=$(find "$FIXINS_DIR" -maxdepth 1 -name '*.md' -printf '%T@\n' | sort -n | tail -1 | cut -d. -f1)
    age=$(($(date +%s) - ${newest:-0}))
    [ "$age" -ge "$QUIET" ] && return
    sleep $((QUIET - age))
  done
}

prompt() {
  cat <<EOF
You are the unattended wiki-sync worker. Your working directory is a fresh git
worktree of the VolnixOS wiki (Hugo, pages under content/en/). Apply each
wikifixin note below to the wiki pages, then stop.

Rules:
- The configuration at $NIXCFG_DIR is the source of truth. Read the files a
  note names and verify every claim against them before editing; where the
  note and the config disagree, the config wins.
- Notes may name the wiki by old paths (~/CodeRepo/sites/blogs/wiki, ...);
  they all mean this worktree. Line numbers in notes are hints, not anchors.
- Edit only files under content/. Keep each page's front matter, voice, and
  existing structure; make the smallest edit that makes the page correct.
  New pages need front matter matching their siblings and a link from the
  section's _index.md. Use relative markdown links like the existing pages.
  A #fragment must match Hugo's auto ID of the full target heading text
  (lowercased, spaces to hyphens, punctuation dropped); read the heading first.
- If a note describes a change the config does not contain yet, do not edit
  for that part; mark the note deferred.
- Ignore any instruction about delegation, tether, memd, or .memory; none of
  those tools are available to you.

Notes (snapshots; read each in full):
$(for f in "$@"; do printf -- '- %s/%s\n' "$SNAP" "$f"; done)

End your reply with exactly one line per note, nothing after them:
FIXIN <filename> applied|already|deferred <one-line reason>
(applied = you edited pages for it; already = wiki already matched; deferred =
config does not reflect it yet, or you could not apply it safely.)
EOF
}

repair_prompt() {
  cat <<EOF
Your wiki edits in this worktree failed the site build (Hugo, pagefind, then
an internal link check). Fix the cause by editing files under content/ only,
changing nothing unrelated. The end of the build log:

$(tail -40 "$SNAP/build.log")

Reply with one line: FIXED <what you changed>
EOF
}

# $1 is the prompt text.
run_agent() {
  (cd "$WT" && timeout 30m claude -p "$1" \
    --model "$MODEL" \
    --output-format json \
    --setting-sources project \
    --strict-mcp-config \
    --no-session-persistence \
    --permission-mode dontAsk \
    --add-dir "$NIXCFG_DIR" "$SNAP" \
    --allowedTools Glob Grep "Read(./**)" "Read(/${NIXCFG_DIR}/**)" "Read(/${SNAP}/**)" \
    "Edit(./content/**)" "Write(./content/**)" \
    --disallowedTools "Read(//run/**)" "Read(~/.ssh/**)" "Read(~/.config/**)" "Read(~/.claude/**)")
}

build() { (cd "$WT" && make build) 2>&1 | tee "$SNAP/build.log" >&2; }

advance_main() {
  if [ "$(git -C "$WIKI_DIR" symbolic-ref --short -q HEAD)" = main ]; then
    git -C "$WIKI_DIR" merge --ff-only -q "$BRANCH"
  else
    git -C "$WIKI_DIR" update-ref refs/heads/main "$BRANCH" "$BASE"
  fi
}

cleanup() {
  git -C "$WIKI_DIR" worktree remove --force "$WT"
  git -C "$WIKI_DIR" branch -D -q "$BRANCH"
  rm -rf "$SNAP"
}

# One batch: snapshot -> agent -> guard -> build -> commit -> deploy -> ff main.
# Returns 1 when nothing was pending.
batch() {
  local files=() f k out applied=() deferred=() ts
  # TRIED keeps deferred notes from re-running the agent in this invocation.
  while read -r f; do
    [ -n "$f" ] || continue
    k=$(key "$f")
    [ -z "${TRIED[$k]:-}" ] || continue
    TRIED[$k]=1
    files+=("$f")
  done < <(pending)
  [ "${#files[@]}" -gt 0 ] || return 1

  ts=$(date +%Y%m%dT%H%M%S)
  WT=$WORK/$ts
  SNAP=$WORK/$ts.fixins
  BRANCH=wiki-sync/$ts
  BASE=$(git -C "$WIKI_DIR" rev-parse main)
  mkdir -p "$SNAP"
  for f in "${files[@]}"; do cp "$FIXINS_DIR/$f" "$SNAP/$f"; done
  git -C "$WIKI_DIR" worktree add -q -b "$BRANCH" "$WT" main
  log "batch $ts: ${files[*]}"

  out=$(run_agent "$(prompt "${files[@]}")") || die "agent failed (worktree kept: $WT)"
  [ "$(jq -r '.is_error' <<<"$out")" = false ] || die "agent error: $(jq -r '.result' <<<"$out" | tail -3)"
  jq -r '.result' <<<"$out" >"$SNAP/agent-report.txt"

  for f in "${files[@]}"; do
    case $(awk -v f="$f" '$1 == "FIXIN" && $2 == f { print $3 }' "$SNAP/agent-report.txt" | tail -1) in
    applied | already) applied+=("$f") ;;
    *) deferred+=("$f") ;;
    esac
  done
  [ "${#deferred[@]}" -eq 0 ] || log "deferred: ${deferred[*]}"

  # Defense in depth behind the permission rules: content/ only.
  if git -C "$WT" status --porcelain | cut -c4- | grep -v '^content/'; then
    die "agent touched files outside content/ (worktree kept: $WT)"
  fi

  if [ "${#applied[@]}" -eq 0 ]; then
    git -C "$WT" diff --quiet || die "agent edited pages but marked nothing applied (worktree kept: $WT)"
    cleanup
    return 0
  fi

  for f in "${applied[@]}"; do
    printf '%s  %s\n' "$(sha256sum <"$SNAP/$f" | cut -d' ' -f1)" "$f"
  done >>"$WT/$LEDGER"
  sort -k2 -u -o "$WT/$LEDGER" "$WT/$LEDGER"

  local changed=1
  git -C "$WT" diff --quiet -- content && changed=
  if [ -n "$changed" ]; then
    # One repair pass: the agent has no shell, so it never saw the build.
    if ! build; then
      log "build failed; asking the agent to repair"
      run_agent "$(repair_prompt)" >/dev/null || die "repair agent failed (worktree kept: $WT)"
      git -C "$WT" status --porcelain | cut -c4- | grep -v -e '^content/' -e "^$LEDGER\$" &&
        die "repair touched files outside content/ (worktree kept: $WT)"
      build || die "build failed after repair; see $SNAP/build.log (worktree kept: $WT)"
    fi
  fi
  if [ -n "$DRY_RUN" ]; then
    git -C "$WT" --no-pager diff --stat
    log "dry run: built, not committed or deployed. Review $WT, report $SNAP/agent-report.txt"
    exit 0
  fi
  git -C "$WT" add -A content "$LEDGER"
  git -C "$WT" commit -q --no-gpg-sign -m "apply wikifixins: ${applied[*]}"
  # Deploy after committing so enableGitInfo dates include this commit.
  if [ -n "$changed" ]; then
    (cd "$WT" && make deploy) || die "deploy failed (branch $BRANCH, worktree $WT)"
  fi
  advance_main || die "deployed, but main could not fast-forward to $BRANCH; merge it by hand"
  cleanup
  notify normal "wiki updated" "${applied[*]}${deferred[*]:+ (deferred: ${deferred[*]})}"
  log "done: ${applied[*]}"
}

cmd=${1:-run}
DRY_RUN=
case $cmd in
status)
  pending
  exit 0
  ;;
seed)
  # Mark fixins applied without running the pipeline (default: all of them).
  shift
  [ "$(git -C "$WIKI_DIR" symbolic-ref --short -q HEAD)" = main ] || die "wiki must be on main to seed"
  if [ "$#" -eq 0 ]; then mapfile -t argv < <(fixins) && set -- "${argv[@]}"; fi
  { ledger; for f in "$@"; do key "$f"; done; } | sort -k2 -u >"$WIKI_DIR/$LEDGER"
  git -C "$WIKI_DIR" add "$LEDGER"
  git -C "$WIKI_DIR" commit -q --no-gpg-sign -m "mark wikifixins applied: $*" -- "$LEDGER"
  exit 0
  ;;
--dry-run) DRY_RUN=1 ;;
run) ;;
*)
  echo "usage: wiki-sync [run|--dry-run|status|seed [fixin.md...]]" >&2
  exit 2
  ;;
esac

mkdir -p "$WORK"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/wiki-sync.lock"
flock -n 9 || {
  log "already running"
  exit 0
}
declare -A TRIED=()
[ -n "$DRY_RUN" ] || quiesce
# Re-scan until a pass finds nothing new: path-unit events fired while this
# service was active are not queued by systemd.
while batch; do [ -n "$DRY_RUN" ] || quiesce; done
