{ lib, appimageTools, fetchurl, p7zip }:

let
  pname = "aionui";
  version = "1.8.26";
  
  src = fetchurl {
    url = "https://github.com/iOfficeAI/AionUi/releases/download/v${version}/AionUi-${version}-linux-x86_64.AppImage";
    hash = "sha256-ce+d/YmLh5WBxn3FgcfxzEcnwFiWktw5UHhB/WHqR8k=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallPhase = ''
    install -m 444 -D ${appimageContents}/${pname}.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace 'Exec=AppRun' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share/ || true
  '';

  meta = with lib; {
    description = "AionUi - Packaged for NixOS using AppImage";
    homepage = "https://github.com/iOfficeAI/AionUi";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
