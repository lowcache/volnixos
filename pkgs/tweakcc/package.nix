{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_10,
  pnpmConfigHook,
  pnpmBuildHook,
  nodejs,
  makeBinaryWrapper,
  autoPatchelfHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "tweakcc";
  version = "4.4.0";

  src = fetchFromGitHub {
    owner = "Piebald-AI";
    repo = "tweakcc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Fduk3Gus8590s3HNg/M8VbuVadBQp2xmuQSK/NSB5vo=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-MvEsrT3ekFqRjXh+46NEWUMpyrJJYjWgO3Oik0wsTd4=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
    pnpmBuildHook
    makeBinaryWrapper
    autoPatchelfHook
  ];

  # node-lief's prebuilt addon links libstdc++
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    CI=true pnpm prune --prod --ignore-scripts
    # Keep only the glibc x86_64/aarch64 addon autoPatchelf can resolve
    find node_modules/.pnpm/node-lief@*/node_modules/node-lief/prebuilds \
      -name '*.node' ! -path '*/linux-${stdenv.hostPlatform.node.arch}/node-lief.node' -delete

    mkdir -p $out/lib/tweakcc
    cp -r dist node_modules package.json $out/lib/tweakcc/
    makeWrapper ${lib.getExe nodejs} $out/bin/tweakcc \
      --add-flags $out/lib/tweakcc/dist/index.mjs \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  meta = {
    description = "Customize Claude Code's system prompts, themes, and UI";
    homepage = "https://github.com/Piebald-AI/tweakcc";
    license = lib.licenses.mit;
    mainProgram = "tweakcc";
    platforms = lib.platforms.linux;
  };
})
