{ config, pkgs, lib, ... }:

{
  home.file.".config/micro/syntax/nix.yaml".text = ''
    filetype: nix

    detect:
        filename: "\\.nix$"

    rules:
        # Brackets and Operators
        - special: "(\\{|\\}|\\(|\\)|\\;|\\(|\\]|\\[|`|\\\\|\\$|<|>|!|=|&|\\|)"

        # Reserved words / Keywords
        - statement: "\\b(assert|else|if|in|inherit|let|rec|then|with|isNull)\\b"

        # Built-in functions/constants
        - identifier: "\\b(true|false|null|import|abort|throw|baseNameOf|dirOf|fetchTarball|map|removeAttrs|scopedImport|toString|derivation)\\b"

        # Comments
        - comment:
            start: "#"
            end: "$"
        - comment:
            start: "/\\*"
            end: "\\*/"

        # Strings
        - constant.string:
            start: "\""
            end: "\""
            skip: "\\\\."
            rules:
                - constant.specialChar: "\\\\."
                - constant.specialChar: "\\$\\{[^}]+\\}"

        # Indented Strings (Double Single Quotes)7
        - constant.string:
            start: "'''"
            end: "'''"
            rules:
                - constant.specialChar: "\\$\\$\\{[^}]+\\}"
                - constant.specialChar: "''''"

        # Numbers
        - constant.number: "\\b[0-9]+\\b"
  '';

  programs = {
    fish = {
      enable = true;
      shellInit = ''
        set -gx EDITOR micro
        set -gx BROWSER brave

        # Toolchain Paths & Persistence
        set -gx GOPATH $HOME/.local/share/go
        set -gx CARGO_HOME $HOME/.cargo
        set -gx RUSTUP_HOME $HOME/.rustup
        set -gx GEM_HOME $HOME/.local/share/gem

        set -gx PATH $HOME/.bin $HOME/.local/bin $HOME/.local/share/npm-global/bin $GOPATH/bin $CARGO_HOME/bin $GEM_HOME/bin $PATH
        set -gx NODE_PATH $HOME/.local/share/npm-global/lib/node_modules
      '';
      interactiveShellInit = ''
        if status is-interactive
            if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
                cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
            end

            set -g fish_greeting
            # Navigation
            alias ..='cd ..'
            alias ...='cd ../..'
            alias ....='cd ../../..'

            if command -v eza > /dev/null
                set -g lo -axG@ --icons --group-directories-first --color=always --octal-permissions
                alias ls="eza $lo"
                alias ll='ls -1l'
                alias lr='ls -R'
                alias lt='ls -T'
                alias la='ls --absolute'
            end

            if command -v infernalinit > /dev/null
                infernalinit
            else if command -v fastfetch > /dev/null
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
      '';
      shellAliases = {
        clear = "printf '033[2J033[3J033[1;1H'";
        celar = "clear";
        claer = "clear";
        c = "clear";
        qii = "qs -c ii";
        edit = "$EDITOR";
        nf = "fastfetch";
        pf = "fastfetch";
        ff = "fastfetch";
        jan = "$HOME/.bin/jan-nix";
        infernal = "infernalinit";
        shutdown = "systemctl poweroff";
        bootbios = "systemctl reboot --firmware";
        wifi = "nmtui";
        mkbann = "figlet.sh";
        wifilist = "nmcli device wifi list";
        nx = "nix";
        nxs = "nix-shell";
        nxr = "nix-rebuild";
        nxrbs = "sudo nixos-rebuild switch --flake /persist/home/lowcache/.nix-config/#infernalnix";
        nxrbb = "sudo nixos-rebuild build --flake /persist/home/lowcache/.nix-config/#infernalnix";
        nxfu = "nix flake update";
        nxfd = "nix search nixpkgs ";
        nxrn = "nix-shell -p ";
        nvrun = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ";
        fooogo = "sudo systemctl start docker-fooocus";
        fooostp = "sudo systemctl stop docker-fooocus";
        forggo = "sudo systemctl start docker-forge";
        forgstp = "sudo systemctl stop docker-forge";
      };
      functions = {
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

            set -l img (realpath $argv[1])
            set -l mon $argv[2]

            # Update the wallpaper.png symlink for matugen service
            ln -sf "$img" ~/Pictures/wallpaper.png

            if test -n "$mon"
              echo "Setting wallpaper for $mon..."
              $script --monitor $mon --image "$img"
            else
              echo "Setting wallpaper globally..."
              $script --image "$img"
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
        priv-sync = ''
          function priv-sync --description "Safely sync live persistent data to priv.bkup"
            set -l REPO_DIR /home/lowcache/Storage/priv.bkup
            set -l LIVE_HOME /persist/home/lowcache

            echo "Starting Safe Sync to priv.bkup..."

            # List of directories to sync
            set -l DIRS Documents Pictures CodeRep unDevel AppImage ZAP-Sessions fonts krita-master .bin crypto-bot

            for dir in $DIRS
                if test -d $LIVE_HOME/$dir
                    echo "Syncing $dir..."
                    rsync -au --progress $LIVE_HOME/$dir/ $REPO_DIR/$dir/
                end
            end

            # Surgical .gemini sync
            echo "Syncing .gemini configuration..."
            mkdir -p $REPO_DIR/.gemini/skills
            rsync -au --progress $LIVE_HOME/.gemini/analytical-agent.yaml $REPO_DIR/.gemini/
            rsync -au --progress $LIVE_HOME/.gemini/nix-agent.yaml $REPO_DIR/.gemini/
            rsync -au --progress $LIVE_HOME/.gemini/skills/ $REPO_DIR/.gemini/skills/

            # SSH and GPG (Backup only)
            echo "Backing up SSH and GPG keys..."
            rsync -au --progress $LIVE_HOME/.ssh/ $REPO_DIR/.ssh/
            rsync -au --progress $LIVE_HOME/.gnupg/ $REPO_DIR/.gnupg/

            echo "Sync complete. You can now commit changes in $REPO_DIR."
          end
        '';
      };
    };
    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "lowcache";
          email = "drawpdeadredd@gmail.com";
        };
        init.defaultBranch = "main";
      };
      signing = {
        signByDefault = true;
        format = "ssh";
        key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      };
    };

    starship.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    micro = {
      enable = true;
      settings = {
        tabsize = 2;
        tabstospaces = true;
        autosu = true;
        colorscheme = "dracula-tc";
        fastdirty = true;
        filemanager = false;
        linter = false;
        multitab = "vsplit";
        parsecursor = true;
        saveundo = true;
        scrollbar = true;
        scrollbarchar = "[]";
        formatonsave = true;
        mkparents = true;
        "nix.formatter" = "nixpkgs-fmt";
        cursorline = true;
        incsearch = true;
        ignorecase = true;
        smartcase = true;
        "lsp.server" = "nix=nil";
      };
    };
  };
  services.ssh-agent.enable = true;
}

