# claude-code with tweakcc customizations baked in at build time.
# Config: ./tweakcc (config.json + any system-prompts/*.md you edited); edit with `make tweakcc`.
{ claude-code, tweakcc }:
claude-code.overrideAttrs (old: {
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
