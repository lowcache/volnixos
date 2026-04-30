
{ config, pkgs, lib, inputs, ... }:

let
  aionui = pkgs.callPackage ./packages/aionui.nix {};
in
{
  nixpkgs.config.allowUnfree = true;
 
  home.username = "nondeus";
  home.homeDirectory = "/home/nondeus";

  # Wrapper Strategy: Preserving Pythonic QML Bridges and other configs.
  # All UI-related configs are symlinked from /persist, which should be a
  # clone of your CachyNixOS or .nix-config repository.
  xdg.configFile = {
    "quickshell".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/quickshell/";
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/hypr";
    "illogical-impulse".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/illogical-impulse";
    "kitty".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/kitty";
    "fastfetch".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/fastfetch";
    "cava".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/cava";
    "fuzzel".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/fuzzel";
    "wlogout".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/wlogout";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "/persist/home/nondeus/.nix-config/dots/starship/starship.toml";
  };
  home.sessionVariables = let 
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
    #XDG_CONFIG_HOME
    #XDG_PICTURES_HOME
    #XDG_CACHE_DIR
    #XDG_DOCUMENTS_DIR
    #XDG_DOWNLOADS_DIR
    
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    GDK_BACKEND = "wayland,x11";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    NIXOS_OZONE_NL = "1";
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  systemd.user.sessionVariables = config.home.sessionVariables;

  # Applications & Workflows
  home.packages = with pkgs; [
    # basedevel
    gcc automake autoconf automake pkg-config
    binutils glibc gdb cmake strace ltrace 
    gperf patch diffutils findutils gawk
    gnugrep gnutar gzip coreutils

    # Personal & Custom applications (non-)
    aionui
    krita
    imagemagick
    krita-plugin-gmic
	chromium
	librewolf
	gemini-cli
	ollama-cuda
	kdePackages.dolphin
	spacedrive
	bibata-cursors
	bibata-cursors-translucent
	papirus-icon-theme
	
    # Core Appplicationbs
    kitty
    adw-gtk3
    brave
    vscodium
    fuzzel
    gedit
	cava
	starship
	swappy
	cliphist
	wl-clipboard
	tesseract
	grim
	slurp
    # Color
    matugen
    hyprpicker
    dart-sass
    python3
    python311Packages.material-color-utilities
	# Hyprland
	hypridle
	hyprlock
	hyprcursor
	hyprland-qt-support
	pamixer
	pavucontrol
	xwayland
	awww
	swww
	waypaper
	hyprpaper
	# Quicktime/Quickshell 
	inputs.quickshell.packages."x86_64-linux".default
	qt5.qtwayland
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
    # Migrated from hybrid config
    fish
    git
    fzf
    eva
    tgpt
    hdrop
    bat
    ripgrep
    flatpak
    feh
    fd
    jq
    bc
    tor
    micro
    fastfetch
    cryptsetup
    htop
    psmisc
    direnv
   	playerctl
   	brightnessctl
   	socat
   	gawk
   	coreutils
   	gojq
   	acpi
   	upower
   	ddcutil
   	networkmanagerapplet
   	# Typography
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
  # https://github.com/lowcache/priv.bkup
  #home.file."Files".source = pkgs.fetchgit {
  #	url = "https://github.com/lowcache/priv.bkup.git";
  #};
  home.persistence."/persist" = {
    directories = [
      ".gemini"
      ".local/share/fish"
      ".local/share/direnv"
      ".local/share/krita" # Persist Krita settings & brushes
      ".local/share/fonts"
      ".local/state/quickshell"
      ".local/share/quickshell"
      ".local/share/illogical-impulse"
      ".local/state/illogical-impulse"
      ".cache/quickshell"
      ".cache/illogical-impulse"
      ".local/share/keyrings"
      ".local/state/wireplumber"
      ".config/dconf"
      ".ssh"
      ".nix-config"
      "Files"
      "CodeRep"
      "Documents"
      "unDevel"
      "Downloads"
      "Pictures"
      "Projects"
      ".config/BraveSoftware"
      ".ZAP" # Persistence for ZAP Config/CA [cite: 91]
      "ZAP-Sessions" # Persistence for ZAP Data [cite: 91]
    ];
  };

  # Git 
  programs.git = {
  	enable = true;
  	settings = {
  	  user = {
  	    name = "lowcache";
  	    email = "drawpdeadredd@gmail.com";
  	  };
  	  init = {
  	    defaultBranch = "main";
  	  };
  	};
  	signing = {
  	  signByDefault = true;
  	  format = "ssh";
  	  key = "~/.ssh/id_ed25519.pub";
  	};
  };
  # Fish shell configuration migrated from hybrid setup
  programs.fish = {
    enable = true;
    shellInit = ''
      set -gx EDITOR micro
      set -gx BROWSER brave
    '';
    interactiveShellInit = ''
      if status is-interactive
          if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
              cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
          end

          set -g fish_greeting

          alias clear "printf '\033[2J\033[3J\033[1;1H'"
          alias celar "clear"
          alias claer "clear"
          alias q "qs -c ii"
			
          alias c='clear'
          alias nf='fastfetch'
          alias pf='fastfetch'
          alias ff='fastfetch'
          alias shutdown='systemctl poweroff'
          alias ts='snapshot.sh'
          alias wifi='nmtui'
          alias ascii='figlet.sh'
          
		  # Navigation 	
          alias ..='cd ..'
          alias ...='cd ../..'
          alias ....='cd ../../..'

          if command -v exa > /dev/null
              set -g lo -axG@ --icons --group-directories-first --color=always --octal-permissions
              alias ls="exa $lo"
              alias ll='ls -1l'
              alias lr='ls -R'
              alias lt='ls -T'
              alias la='ls --absolute'
          end

          if command -v fastfetch > /dev/null
              fastfetch
          end

          function auto_ls --on-variable PWD
              if status is-interactive
                  ls
              end
          end
      end

      function cd --description "Change directory with file handling"
          if test (count $argv) -eq 0
              builtin cd
              return
          end
          set -l t $argv[1]
          if test -f "$t"
              set t (dirname "$t")
          end
          builtin cd "$t"
      end

      direnv hook fish | source
    '';
    shellAliases = {
      clear = "printf '\\033[2J\\033[3J\\033[1;1H'";
      celar = "clear";
      claer = "clear";
      pamcan = "pacman";
      qii = "qs -c ii";
      edit = "$EDITOR";
      nx = "nix";
      nxs = "nix-shell";
      nxr = "nix-rebuild";
      nxrb = "sudo nixos-rebuild switch --flake /persist/home/nondeus/.nix-config/#nondeus ";
      nxfd = "nix --extra-experimental-features 'nix-command flakes' search nixpkgs";
      nxrn = "nix-shell --extra-experimental-features 'nix-command flakes' -p ";	
    };
    functions = {
      better_cd = ''
        function better_cd
          set -l t $argv[1]
          if test -z "$t"
            builtin cd
            return
          end
          if test -f "$t"
            set t (dirname "$t")
          end
          builtin cd "$t"
        end
      '';
      extract = ''
        function extract --description "Expand/extract archives"
          for file in $argv
            if test -f "$file"
              switch "$file"
                case "*.tar.bz2" "*.tbz2" "*.tbz"
                  tar xvjf "$file"
                case "*.tar.gz" "*.tgz"
                  tar xvzf "$file"
                case "*.tar.xz" "*.txz" "*.tar.lzma"
                  tar xvJf "$file"
                case "*.tar.zst"
                  tar --zstd -xvf "$file"
                case "*.tar"
                  tar xvf "$file"
                case "*.zip" "*.jar"
                  unzip "$file"
                case "*.deb"
                  ar -x "$file"
                case "*.bz2"
                  bunzip2 "$file"
                case "*.gz"
                  gunzip "$file"
                case "*.xz" "*.lzma"
                  unxz "$file"
                case "*.zst"
                  unzstd "$file"
                case "*"
                  echo "'$file' cannot be extracted via extract"
              end
            else
              echo "'$file' is not a valid file"
            end
          end
        end
      '';
      setwall = ''
        function setwall --description "Set wallpaper for a specific monitor or globally"
          set -l script ~/.config/quickshell/ii/scripts/colors/switchwall.sh

          if test (count $argv) -eq 0
            echo "Usage: setwall <image_path> [monitor_name]"
            echo "Example: setwall ~/Pictures/wall.png DP-1"
            return 1
          end

          set -l img $argv[1]
          set -l mon $argv[2]

          if test -n "$mon"
            echo "Setting wallpaper for $mon..."
            $script --monitor $mon --image $img
          else
            echo "Setting wallpaper globally..."
            $script --image $img
          end
        end
      '';
      gpgkey = ''
        function gpgkey
          set -x GPG_TTY (tty)
          read -P "Enter your full name: " user_name
          read -P "Enter your email address: " user_email
          read -P "Enter a comment (optional): " user_comment
          read -S -P "Enter a passphrase: " key_passphrase
          echo

          set temp_batch_file (mktemp)
          echo "%echo Generating GPG key" > $temp_batch_file
          echo "Key-Type: RSA" >> $temp_batch_file
          echo "Key-Length: 4096" >> $temp_batch_file
          echo "Key-Usage: sign,encrypt" >> $temp_batch_file
          echo "Name-Real: $user_name" >> $temp_batch_file
          echo "Name-Email: $user_email" >> $temp_batch_file
          if test -n "$user_comment"
            echo "Name-Comment: $user_comment" >> $temp_batch_file
          end
          echo "Expire-Date: 0" >> $temp_batch_file
          echo "Passphrase: $key_passphrase" >> $temp_batch_file
          echo "%commit" >> $temp_batch_file
          echo "%echo Done" >> $temp_batch_file

          echo "Generating GPG key..."
          gpg --batch --gen-key $temp_batch_file

          if test $status -ne 0
            echo "Error: GPG key generation failed."
            rm -f $temp_batch_file
            return 1
          end

          set key_fingerprint (gpg --list-keys --with-colons $user_email | grep '^fpr' | tail -n 1 | cut -d':' -f10)
          set safe_email (echo $user_email | tr -d ' ')
          gpg --armor --export $user_email > "./$safe_email.gpg.asc"

          echo "GPG key created! Key Fingerprint: $key_fingerprint"
          echo "Armored public key exported to: ./$safe_email.gpg.asc"
          rm -f $temp_batch_file
        end
      '';
      rmspcs = ''
        function rmspcs --description "Remove spaces from filenames"
          set -l target_dir .
          if count $argv > /dev/null
            set target_dir $argv[1]
          end
          if not test -d $target_dir
            echo "Error: '$target_dir' is not a directory."
            return 1
          end
          find $target_dir -depth -name "* *" | while read -l file
            set -l dir (dirname "$file")
            set -l old_name (basename "$file")
            set -l new_name (string replace -a " " "_" "$old_name")
            echo "Renaming: $old_name -> $new_name"
            mv "$file" "$dir/$new_name"
          end
        end
      '';
    };
  };

  # Starship prompt. The config is now managed via the Wrapper Strategy.
  programs.starship.enable = true;
  programs.direnv = {
  	enable = true;
  	nix-direnv.enable = true;
  };
  # Micro editor settings migrated from hybrid config.
  programs.micro = {
    enable = true;
    settings = {
      autosu = true;
      colorscheme = "dracula-tc";
      fastdirty = true;
      filemanager = false;
      linter = false;
      multitab = "hsplit";
      parsecursor = true;
      saveundo = true;
      scrollbar = true;
      scrollbarchar = "[]";
    };
  };

  # Matugen color engine service.
  systemd.user.services.matugen = {
    Unit.Description = "Declarative Matugen Color Engine";
    Service = {
      # NOTE: Path updated. Ensure a wallpaper exists at this location in /persist.
      ExecStart = "${pkgs.matugen}/bin/matugen apply -i /persist/home/nondeus/Pictures/wallpaper.png";
      Type = "oneshot";
    };
  };

  home.stateVersion = "24.11";

  home.pointerCursor = {
    package = pkgs.bibata-cursors-translucent;
    name = "Bibata-Modern-Translucent";
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk4 = {
      theme = null;
    };
    cursorTheme = {
      name = "Bibata-Modern-Translucent";
      package = pkgs.bibata-cursors-translucent;
      size = 24;
    };
  };
}
