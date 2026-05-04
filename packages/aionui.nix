{ lib, appimageTools, fetchurl }:

let
  pname = "AionUi";
  version = "1.8.26";
  
  src = fetchurl {
    url = "https://github.com/iOfficeAI/AionUi/releases/download/v${version}/AionUi-${version}-linux-x86_64.AppImage";
    hash = "sha256-ce+d/YmLh5WBxn3Fo/3RzEcnwFiWktw5UHhB/WHqR8k=";
  };

  appimageContents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallPhase = ''
    mkdir -p $out/share/applications
    cp -r ${appimageContents}/*.desktop $out/share/applications/
    chmod +w $out/share/applications/*.desktop
    sed -i "s|Exec=.*|Exec=${pname}|g" $out/share/applications/*.desktop
    sed -i "s|Icon=.*|Icon=${pname}|g" $out/share/applications/*.desktop
    sed -i "/NoDisplay=/d" $out/share/applications/*.desktop
    
    # Try to install icons from various possible locations in the AppImage
    mkdir -p $out/share/icons/hicolor/512x512/apps
    cp -r ${appimageContents}/usr/share/icons $out/share/ 2>/dev/null || \
    cp -r ${appimageContents}/share/icons $out/share/ 2>/dev/null || \
    find ${appimageContents} -maxdepth 1 -name "*.png" -exec cp {} $out/share/icons/hicolor/512x512/apps/${pname}.png \; || true
  '';

  meta = with lib; {
    description = "AionUi - Packaged for NixOS using AppImage";
    homepage = "https://github.com/iOfficeAI/AionUi";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
}
