# Built the way upstream's `just release` + pack.sh lay out a release, replacing
# llm-agents.nix's run-from-source wrapper (missing nodecode-context, argv bug).
{
  lib,
  stdenv,
  fetchFromGitHub,
  sbcl,
  openssl,
  sqlite,
  patchelf,
  jq,
}:
let
  # Must equal the commit pinned in nodecode's src/cells/bundle.json (checked in the build).
  cellsSrc = fetchFromGitHub {
    owner = "nodecode-ai";
    repo = "cells";
    rev = "780fbc5eeb65ca4c85decc6f2c3f7ff3dc324d13";
    hash = "sha256-RkZ1S2K3Wd05QcmCBTPY4fAsuJZU8UOfnmN4Jm0VofM=";
  };

  # nodecode.asd's :depends-on; the shipped cells need nothing beyond these.
  sbclEnv = sbcl.withPackages (ps: [
    ps.bordeaux-threads
    ps.shasht
    ps.cl-ppcre
    ps.dexador
    ps.flexi-streams
    ps.alexandria
    ps.sqlite
    ps.cl_plus_ssl
    ps.cl-base64
    ps.clack
    ps.clack-handler-hunchentoot
    ps.websocket-driver
    ps.ironclad
  ]);

  # The image reopens libsqlite3/libssl by soname at every start; the dump copies
  # the runtime it runs on, so a RUNPATH set there is inherited by the binary.
  runtimeLibPath = lib.makeLibraryPath [
    openssl
    sqlite
  ];
in
stdenv.mkDerivation {
  pname = "nodecode";
  version = "0.0.1-unstable-2026-10-24";

  src = fetchFromGitHub {
    owner = "nodecode-ai";
    repo = "nodecode";
    rev = "c6418bcbe3b245788eb38bb2c08d1632d5b11f2f";
    hash = "sha256-94DAp6odMF+WHomWEa2sisCDTpZfg/SN97qOSZkOeUs=";
  };

  nativeBuildInputs = [
    sbclEnv
    patchelf
    jq
  ];

  # The executable is the SBCL runtime with the core appended: strip/patchelf would corrupt it.
  dontStrip = true;
  dontPatchELF = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR

    test "$(jq -r .commit src/cells/bundle.json)" = "${cellsSrc.rev}" \
      || { echo "nodecode: bundle.json pins a different cells commit than cellsSrc" >&2; exit 1; }
    jq -r '.cells | to_entries[] | "\(.key) \(.value)"' src/cells/bundle.json |
      while read -r local hub; do
        mkdir -p "src/cells/$local"
        cp -r --no-preserve=mode "${cellsSrc}/$hub/." "src/cells/$local/"
      done
    find src/cells -type d -name test -prune -exec rm -rf {} +

    # Lay out the release tree at its final path: compiled cell fasls record source paths.
    root=$out/lib/nodecode
    mkdir -p $root/src
    cp -r src/src src/cells src/nodecode.asd $root/src/
    cp -r resources LICENSE NOTICE $root/

    rt=$PWD/rt/sbcl
    install -Dm755 ${sbcl}/bin/sbcl $rt
    patchelf --add-rpath ${runtimeLibPath} $rt
    # Reuse the withPackages wrapper's ASDF environment, but dump on the patched runtime.
    eval "$(sbcl --noinform --non-interactive --eval '(require :asdf)' \
      --eval '(dolist (v (list "CL_SOURCE_REGISTRY" "ASDF_OUTPUT_TRANSLATIONS" "LD_LIBRARY_PATH")) (format t "export ~a=~s~%" v (or (uiop:getenv v) "")))')"
    export SBCL_HOME=${sbcl}/lib/sbcl

    # justfile `release`: heap and stack sizes are baked into the dumped binary.
    (cd $root/src && $rt --core ${sbcl}/lib/sbcl/sbcl.core \
      --dynamic-space-size 8192 --control-stack-size 8MB --noinform --non-interactive \
      --eval '(require :asdf)' \
      --eval '(push (truename ".") asdf:*central-registry*)' \
      --eval '(push (truename "cells/context/") asdf:*central-registry*)' \
      --eval '(asdf:make :nodecode/bin :force (list "nodecode/bin"))')
    test -s $root/nodecode && test -x $root/nodecode

    # pack.sh's gate: a shipped cell that fails to load fails the build. The fasls are
    # then dropped: store mtimes (1970) predate the image's ASDF stamps, so a launch
    # would recompile into the read-only src/fasl. Without it, cells compile to the user cache.
    bash src/tools/compile-cells.sh $root/nodecode $root/src/cells $root/src/fasl
    rm -rf $root/src/fasl

    runHook postBuild
  '';

  # The binary finds src/ beside its resolved path, so bin/ gets a symlink, not a wrapper.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ln -s ../lib/nodecode/nodecode $out/bin/nodecode
    runHook postInstall
  '';

  meta = {
    description = "Self-modifying agent organism in SBCL";
    homepage = "https://github.com/nodecode-ai/nodecode";
    license = lib.licenses.mit;
    mainProgram = "nodecode";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
