# claude-code with tweakcc customizations baked in at build time.
# Config: ./tweakcc (config.json + any system-prompts/*.md you edited); edit with `make tweakcc`.
#
# Pinned to claude-code 2.1.296: the newest version tweakcc 4.4.0 has
# prompt data for (data/prompts/prompts-2.1.296.json). nixpkgs' claude-code
# is currently 2.1.321, which tweakcc 4.4.0 does not support — postInstall
# fails with `install: cannot stat .../prompts-2.1.321.json`.
# Re-pin here (and update the manifest file) when tweakcc cuts a release
# supporting a newer claude-code, or bump tweakcc to main.
{
  claude-code,
  tweakcc,
  lib,
}:
let
  pinnedClaudeCode = claude-code.override {
    manifest = lib.importJSON ./manifest-2.1.296.zst.json;
  };
in
pinnedClaudeCode.overrideAttrs (old: {
  pname = "claude-code-tweaked";
  nativeBuildInputs = old.nativeBuildInputs ++ [ tweakcc ];

  # postInstall, not later: tweakcc's LIEF parser segfaults on autoPatchelf's rewritten ELF.
  # The prompt data comes from tweakcc's source, so an unsupported claude-code version fails here.
  postInstall = (old.postInstall or "") + ''
    export HOME=$TMPDIR TWEAKCC_CONFIG_DIR=$TMPDIR/tweakcc
    cp -r ${./tweakcc} $TWEAKCC_CONFIG_DIR
    chmod -R u+w $TWEAKCC_CONFIG_DIR
    install -Dm644 ${tweakcc.src}/data/prompts/prompts-${old.version}.json \
      $TWEAKCC_CONFIG_DIR/prompt-data-cache/prompts-${old.version}.json
    TWEAKCC_CC_INSTALLATION_PATH=$out/bin/.claude-wrapped tweakcc --apply --yes
  '';
})
