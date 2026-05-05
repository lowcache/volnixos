{ config, pkgs, lib, ... }:

let
  # We define the entire set of session variables once in this let block.
  sessionVariables = let
    qtDependencies = with pkgs; [
      qt6.qtwayland
      qt6.qtsvg
      qt6.qt5compat
      qt6.qtdeclarative
      qt6.qtpositioning
      qt6.qtmultimedia
      qt6.qtquicktimeline
      qt6.qtimageformats
      qt6.qtvirtualkeyboard
      qt6.qtsensors
      qt6.qttools
      qt6.qttranslations
      qt6.qtwebsockets
      qt6.qtshadertools
      qt6.qtscxml
      kdePackages.kirigami.unwrapped
      kdePackages.kirigami-addons
      kdePackages.breeze-icons
      kdePackages.qqc2-desktop-style
      kdePackages.syntax-highlighting
    ];
  in {
    QML2_IMPORT_PATH = pkgs.lib.concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/qml:${pkg}/lib/qml") qtDependencies + ":/home/nondeus/.config/quickshell/ii";
    QML_IMPORT_PATH = pkgs.lib.concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/qml:${pkg}/lib/qml") qtDependencies + ":/home/nondeus/.config/quickshell/ii";
    QT_PLUGIN_PATH = pkgs.lib.concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/plugins:${pkg}/lib/plugins") qtDependencies;
    # ENV VARS
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "Hyprland";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    GDK_BACKEND = "wayland,x11";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    # Wayland support for Electron/Chromium
    NIXOS_OZONE_WL = "1";
  };

in
# This now returns a single, valid attribute set.
{
  # We assign the set we defined above to both options.
  home = {
    sessionVariables = sessionVariables;
      pointerCursor = {
        package = pkgs.bibata-cursors-translucent;
        name = "Bibata-Modern-Translucent";
        size = 24;
        gtk.enable = true;
        x11.enable = true;
      };
  };
  systemd = {
    user = {
      sessionVariables = sessionVariables;
      services.matugen = {
        Unit.Description = "Declarative Matugen Color Engine";
        Service = {
          # NOTE: Path updated. Ensure a wallpaper exists at this location in /persist.
          ExecStart = "${pkgs.matugen}/bin/matugen apply -i /persist/home/nondeus/Pictures/wallpaper.png";
          Type = "oneshot";
        };
      };
    };
  };
}
