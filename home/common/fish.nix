{
  programs.fish = {
    enable = true;

    # Toolchain roots + PATH. Kept in one module so PATH is always assembled
    # AFTER the vars it interpolates ($GOPATH/$CARGO_HOME/$GEM_HOME) — splitting
    # these across modules would make the merge order load-bearing.
    shellInit = ''
      set -gx EDITOR micro

      # Toolchain Paths & Persistence
      set -gx GOPATH $HOME/.local/share/go
      set -gx CARGO_HOME $HOME/.cargo
      set -gx RUSTUP_HOME $HOME/.rustup
      set -gx GEM_HOME $HOME/.local/share/gem

      set -gx PATH $HOME/.bin $HOME/.local/bin $HOME/.local/share/npm-global/bin $GOPATH/bin $CARGO_HOME/bin $GEM_HOME/bin $PATH
      set -gx NODE_PATH $HOME/.local/share/npm-global/lib/node_modules

      # sops: native age identity, so `sops nixos/host-secrets.yaml` edits need no env prefix
      set -gx SOPS_AGE_KEY_FILE $HOME/.config/sops/age/keys.txt
    '';

    interactiveShellInit = ''
      if status is-interactive
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

          if command -v volinit > /dev/null
              volinit
          else if command -v fastfetch > /dev/null
              fastfetch
          end

          # Agent-agnostic project scaffolding: claude-code runs
          # agent-scaffold via its SessionStart hook; wrap other agent
          # CLIs so any session entry point scaffolds .model/ + .memory/
          # first. Deliberately NOT a PWD hook — merely cd-ing into a
          # cloned third-party repo must not litter it with scaffolding.
          function agy --wraps agy
              command -q agent-scaffold; and agent-scaffold
              command agy $argv
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
      celar = "clear";
      claer = "clear";
      c = "clear";
      color = "colorhex";
      chex = "colorhex";
      edit = "$EDITOR";
      nf = "fastfetch";
      pf = "fastfetch";
      ff = "fastfetch";
      nx = "nix";
      nxup = "nix flake update ";
      nxfd = "nix search nixpkgs ";
      nxsh = "nix-shell -p ";
    };

    functions = {
      colorhex = {
        description = "Colorize hex color codes in input text";
        body = ''
              python3 -c '
          import sys, re, os

          def hex_to_rgb(hex_str):
              hex_str = hex_str.lstrip("#")
              if len(hex_str) == 3:
                  hex_str = "".join([c*2 for c in hex_str])
              return int(hex_str[0:2], 16), int(hex_str[2:4], 16), int(hex_str[4:6], 16)

          def colorize(match):
              hex_code = match.group(0)
              try:
                  r, g, b = hex_to_rgb(hex_code)
                  luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b)
                  fg_color = "0" if luminance > 128 else "15" # black or bright white text
                  return f"\x1b[48;2;{r};{g};{b}m\x1b[38;5;{fg_color}m {hex_code} \x1b[0m"
              except Exception:
                  return hex_code

          pattern = re.compile(r"#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3}")

          if len(sys.argv) > 1:
              for arg in sys.argv[1:]:
                  if arg == "-":
                      for line in sys.stdin:
                          sys.stdout.write(pattern.sub(colorize, line))
                  elif os.path.exists(arg):
                      try:
                          with open(arg, "r") as f:
                              for line in f:
                                  sys.stdout.write(pattern.sub(colorize, line))
                      except Exception:
                          sys.stdout.write(pattern.sub(colorize, arg) + "\n")
                  else:
                      sys.stdout.write(pattern.sub(colorize, arg) + "\n")
          else:
              for line in sys.stdin:
                  sys.stdout.write(pattern.sub(colorize, line))
          ' $argv
        '';
      };
      extract = {
        description = "Expand/extract archives";
        body = ''
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
        '';
      };
      gpgkey = {
        description = "creates gpg keyn and displays armored output";
        body = ''
          set -x GPG_TTY (tty)
          read -P "Enter your full name: " user_name
          read -P "Enter your email address: " user_email
          read -P "Enter a comment (optional): " user_comment
          read -S -P "Enter a passphrase: " key_passphrase
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
        '';
      };
      rmspcs = {
        description = "Remove spaces from filenames";
        body = ''
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
        '';
      };
      ai = {
        description = "Run an AI agent tool from llm-agents.nix on-the-fly";
        body = ''
          if test (count $argv) -eq 0
            echo "Usage: ai <agent-tool> [args...]"
            echo "Example: ai ralph-tui"
            return 1
          end
          nix run "github:numtide/llm-agents.nix#$argv[1]" -- $argv[2..-1]
        '';
      };
      ai-shell = {
        description = "Spawn an ephemeral shell with one or more tools from llm-agents.nix";
        body = ''
          if test (count $argv) -eq 0
            echo "Usage: ai-shell <tool1> <tool2> ..."
            echo "Example: ai-shell ralph-tui apm ck"
            return 1
          end
          set -l pkgs
          for pkg in $argv
            set pkgs $pkgs "github:numtide/llm-agents.nix#$pkg"
          end
          nix shell $pkgs
        '';
      };
    };
  };
}
