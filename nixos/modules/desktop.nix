# Graphical session: greetd/tuigreet launching niri via uwsm, plus the xdg
# portal routing overrides. niri itself is enabled in programs.nix.
{
  config,
  pkgs,
  ...
}:
{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # niri is the sole session. niri.desktop comes from programs.niri in
        # programs.nix; launched via uwsm (uwsm binary lives in systemPackages).
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --cmd 'uwsm start niri.desktop'";
        user = "greeter";
      };
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # Opt-in since 26.11. GUI tools that self-elevate (gparted) call pkexec,
  # which only works through the setuid wrapper plus a polkit agent (Noctalia's).
  security.polkit.enablePkexecWrapper = true;
}
