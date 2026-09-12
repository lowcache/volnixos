{
  pkgs,
  inputs,
  ...
}:

{
  # Noctalia Shell v5.0.0 + the portable shell/tooling layer shared with the
  # nix-on-droid config (see home/common/). Only volnix-specific shell surface
  # lives in this file: the niri/Noctalia session, sops-nix runtime secrets, the
  # impermanence-aware TMPDIR, and hardware/systemd-bound aliases.
  imports = [
    inputs.noctalia.homeModules.default
    ./common
  ];

  programs = {
    # home/noctalia.nix — Noctalia v5 shell (package + enable only).
    # Config is deliberately NOT managed here: ~/.config/noctalia is an out-of-store
    # symlink to dots/noctalia (see persist.nix), following the live-edit dotfile
    # pattern
    noctalia.enable = true;
    # Brave Browser (primary). programs.chromium both installs the package and
    # applies the Wayland/GPU command-line flags. Floorp (backup) is in pkgs.nix.
    chromium = {
      enable = true;
      package = pkgs.brave;
      commandLineArgs = [
        "--ozone-platform-hint=auto"
        "--disable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder,WaylandWpColorManagerV1"
        "--disable-gpu-memory-buffer-video-frames"
        "--enable-features=TouchpadOverscrollHistoryNavigation"
        "--enable-gpu-rasterization"
        "--enable-oop-rasterization"
        "--enable-zero-copy"
      ];
    };

    fish = {
      shellInit = ''
        set -gx BROWSER brave

        # Scratch/temp on the roomy Storage disk, NOT the 4G impermanence tmpfs
        # root (which fills fast and breaks builds with "broken pipe"/ENOSPC).
        test -d $HOME/Storage/tmp; or mkdir -p $HOME/Storage/tmp
        set -gx TMPDIR $HOME/Storage/tmp

        # --== SOPS protected API key exposure ==--
        # the following steps are for adding a new API key that needs to be exposed as an environment variable. 
        # 1. make sops-edit -> add api key to the list
        # 2. micro ~/.nix-config/nixos/modules/secrets.nix -> declare the key with owner = username;
        # 3. use template below to add the new key

        # New key template:
        # test -r /run/secrets/{api_key_name}
        # and set -gx {API_KEY_NAME} (cat /run/secrets/{api_key_name})

        # Gemini API key — decrypted at runtime by sops-nix to /run/secrets/gemini_api_key
        test -r /run/secrets/gemini_api_key
        and set -gx GEMINI_API_KEY (cat /run/secrets/gemini_api_key)

        # Github token - sops-nix to /run/secrets/gh_token
        test -r /run/secrets/gh_token
        and set -gx GH_TOKEN (cat /run/secrets/gh_token)

        # Phone-agent bearer token - sops-nix to /run/secrets/phone_agent_token;
        # consumed by the phone-agent MCP server in .model/.claude/.mcp.json
        test -r /run/secrets/phone_agent_token
        and set -gx PHONE_AGENT_TOKEN (cat /run/secrets/phone_agent_token)

        # apify
        test -r /run/secrets/apify_api_key
        and set -gx APIFY_API_KEY (cat /run/secrets/apify_api_key)

        # openrouter
        test -r /run/secrets/openrouter_api_key
        and set -gx OPENROUTER_API_KEY (cat /run/secrets/openrouter_api_key)

        # twine 
        test -r /run/secrets/twine_api_key
        and set -gx TWINE_API_KEY (cat /run/secrets/twine_api_key)
      '';
      shellAbbrs = {
        # Anonymous mode: arm/disarm egress via the net-gate Tor VM. The target
        # now asserts a real Tor exit before it reports success, so the tor-check
        # chaser is gone — if `anon-on` returns 0, traffic left through Tor.
        # Disarming re-seals the uid jail and reaps anon.slice.
        anon-on = "sudo systemctl start anonymous.target";
        anon-off = "sudo systemctl stop anonymous.target";
        anon-status = "systemctl --no-pager status anonymous.target anon-jail anon-routing anon-check anon-watch";
      };
      shellAliases = {
        jan = "$HOME/.bin/jan-nix";
        infernal = "infernalinit";
        shutdown = "systemctl poweroff";
        bootbios = "systemctl reboot --firmware";
        wifi = "nmtui";
        mkbann = "figlet.sh";
        wifilist = "nmcli device wifi list";
        nvrun = "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ";
        stbldff-on = "sudo systemctl start docker-fooocus";
        stbldff-off = "sudo systemctl stop docker-fooocus";
        # NOTE: no `forge` oci-container is declared in nixos/configuration.nix yet;
        # these aliases target a non-existent docker-forge.service. Re-enable once
        # the forge container is defined (see memory/todo.md).
        # forggo = "sudo systemctl start docker-forge";
        # forgstp = "sudo systemctl stop docker-forge";
      };
      functions = {
        tablet = {
          description = "Phone S-Pen as a Krita tablet over USB (Weylus + adb reverse)";
          body = ''
            if test "$(adb -d get-state 2>/dev/null)" != device
                echo "No authorized USB device. Plug in USB-C, enable USB debugging, accept the prompt on the phone."
                adb devices
                return 1
            end
            adb -d reverse tcp:1701 tcp:1701; or begin
                echo "adb reverse failed"
                return 1
            end
            echo "Weylus -> open http://localhost:1701 in Chrome/Samsung Internet on the phone."
            echo "Ctrl-C here to stop."
            weylus --no-gui --bind-address 127.0.0.1 --web-port 1701
            adb -d reverse --remove tcp:1701 2>/dev/null
            echo "tablet: stopped, USB tunnel removed."
          '';
        };
        setwall = {
          description = "Set wallpaper for a specific monitor or globally";
          body = ''
            if test (count $argv) -eq 0
              echo "Usage: setwall <image_path> [monitor_name]"
              echo "Example: setwall ~/Pictures/wall.png DP-1"
              return 1
            end
            set -l img (realpath $argv[1])
            set -l mon $argv[2]
            # Convention symlink (referenced elsewhere); harmless on either session.
            ln -sf "$img" ~/Pictures/wallpaper.png
            # niri + Noctalia: WALLPAPER ONLY. No color logic — Noctalia owns the
            # colorscheme (its own templates write kitty/niri/fuzzel/cava/starship),
            # and nothing here clobbers it. noctalia msg wallpaper-set is persisted.
            if test -n "$mon"
              noctalia msg wallpaper-set "$mon" "$img"
            else
              noctalia msg wallpaper-set "$img"
            end
          '';
        };
      };
    };
  };
  services.ssh-agent.enable = true;
}
