{ config, pkgs, lib, ... }:

{
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

        set -gx PATH $HOME/.local/share/npm-global/bin $GOPATH/bin $CARGO_HOME/bin $GEM_HOME/bin $PATH
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
        clear = "printf '\033[2J\033[3J\033[1;1H'";
        celar = "clear";
        claer = "clear";
        c = "clear";
        qii = "qs -c ii";
        edit = "$EDITOR";
        nf = "fastfetch";
        pf = "fastfetch";
        ff = "fastfetch";
        shutdown = "systemctl poweroff";
        bootbios = "systemctl reboot --firmware";
        wifi = "nmtui";
        mkbann = "figlet.sh";
        wifilist = "nmcli device wifi list";
        nx = "nix";
        nxs = "nix-shell";
        nxr = "nix-rebuild";
        nxrb = "sudo nixos-rebuild switch --flake /persist/home/nondeus/.nix-config/#nondeus";
        nxfd = "nix --extra-experimental-features 'nix-command flakes' search nixpkgs ";
        nxrn = "nix-shell --extra-experimental-features 'nix-command flakes' -p ";	
        nvrun = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ";
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
    git = {
      enable = true;
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
        key = "~/.ssh/id_ed25519.pub";
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
      };
    };
  };
}

