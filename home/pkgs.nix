{ config, pkgs, lib, inputs, ... }:

let 
  aionui = pkgs.callPackage ../packages/aionui.nix {};
in
{
  home = {
    packages = let 
      aionui-build = with pkgs; [
      	aionui
      ];
      basedevel = with pkgs; [
	    gcc automake autoconf automake pkg-config binutils glibc 
	    gdb cmake strace ltrace gperf patch diffutils findutils 
	    gawk gnugrep gnutar gzip coreutils go dart-sass python3
	    python3Packages.pillow
	    python3Packages.click
	    python3Packages.loguru
	    python3Packages.tqdm
	    python3Packages.pygobject3
	    python3Packages.requests
	    python3Packages.material-color-utilities
        glib nodejs corepack
	  ];
	  quickshell = with pkgs; [
	    inputs.quickshell.packages."x86_64-linux".default
        qt5.qtwayland qt6.qtwayland qt6.qtsvg qt6.qt5compat
        qt6.qtdeclarative qt6.qtpositioning qt6.qtmultimedia
        qt6.qtquicktimeline qt6.qtimageformats qt6.qtvirtualkeyboard
	    qt6.qtsensors qt6.qttools qt6.qttranslations qt6.qtwebsockets
	    qt6.qtshadertools qt6.qtscxml
	    kdePackages.kirigami.unwrapped kdePackages.kirigami-addons
	    kdePackages.breeze-icons kdePackages.qqc2-desktop-style
	    kdePackages.syntax-highlighting kdePackages.dolphin
	    bibata-cursors bibata-cursors-translucent
	  ];
      hyprland = with pkgs; [
		hypridle hyprlock hyprcursor hyprland-qt-support pamixer
		pavucontrol xwayland awww waypaper hyprpaper adw-gtk3
	    cliphist hyprpicker fuzzel kitty krita-plugin-gmic krita
	    imagemagick chromium librewolf spacedrive papirus-icon-theme
	    gsettings-desktop-schemas brave vscodium gedit cava swappy
	    wl-clipboard grim slurp matugen networkmanagerapplet
	  ];
      typography = with pkgs; [
		material-symbols
		nerd-fonts.symbols-only
		nerd-fonts.jetbrains-mono
	    nerd-fonts.ubuntu-sans
	    nerd-fonts.sauce-code-pro
	    nerd-fonts.intone-mono
	    nerd-fonts.martian-mono
	    nerd-fonts.roboto-mono
	    nerd-fonts.anonymice
	    nerd-fonts.hack
	    nerd-fonts.hurmit
	    nerd-fonts.hasklug
	    nerd-fonts.geist-mono
		nerd-fonts.commit-mono
		nerd-fonts.code-new-roman
		nerd-fonts.blex-mono
		nerd-fonts.envy-code-r
		nerd-fonts.victor-mono
		nerd-fonts.recursive-mono
		nerd-fonts.departure-mono
		nerd-fonts.zed-mono
		nerd-fonts.atkynson-mono
	  ];
	  terminal = with pkgs; [
	    fish git fzf eza tgpt hdrop bat ripgrep flatpak
	    feh fd jq bc tor micro fastfetch cryptsetup htop
		psmisc direnv playerctl brightnessctl socat gawk
		acpi upower ddcutil gemini-cli ollama-cuda
      ];	
    in
	  aionui-build ++ terminal ++ typography ++ hyprland ++ quickshell ++ basedevel;
  };
}
