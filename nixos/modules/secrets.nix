# Host secrets, sops-managed. Age key = the persisted host SSH key
# (/persist/etc/ssh/ssh_host_ed25519_key). File layout and trust boundaries:
# see nixos/.sops.yaml — host-secrets.yaml is encrypted to admin + host key;
# vm-secrets.yaml (used by net-gate) to admin + net-gate's own key.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  # Secrets a tool reads from the environment; each is decrypted to a file
  # owned by the user. No `wrap`: exported in every fish shell, for keys several
  # agent tools read implicitly. `wrap = pkg`: exported only into that command,
  # through a same-named wrapper that shadows it on PATH.
  envSecrets = {
    GEMINI_API_KEY.secret = "gemini_api_key";
    OPENROUTER_API_KEY.secret = "openrouter_api_key";
    # Expanded by .claude/.mcp.json and OmO's mcp.json; claude is self-installed
    # in ~/.local/bin, ahead of anything a Nix wrapper could put on PATH.
    PHONE_AGENT_TOKEN.secret = "phone_agent_token";
    GH_TOKEN = {
      secret = "gh_token";
      wrap = pkgs.gh;
    };
    # Write token for volnixos.cachix.org (pushing locally built kernels).
    CACHIX_AUTH_TOKEN = {
      secret = "cachix_auth_token";
      wrap = pkgs.cachix;
    };
    # Bearer token for tb-bridge (home/thunderbird-bridge.nix); without it any
    # local uid, the anon one included, could read and send mail via :7700.
    TB_AUTH_TOKEN = {
      secret = "tb_auth_token";
      wrap = pkgs.thunderbird-cli;
    };
  };

  pathOf = s: config.sops.secrets.${s.secret}.path;
  global = lib.filterAttrs (_: s: !(s ? wrap)) envSecrets;
  wrapped = lib.filterAttrs (_: s: s ? wrap) envSecrets;

  wrapper =
    var: s:
    lib.hiPrio (
      pkgs.writeShellApplication {
        name = s.wrap.meta.mainProgram;
        text = ''
          if [ -z "''${${var}:-}" ] && [ -r ${pathOf s} ]; then
            ${var}=$(< ${pathOf s})
            export ${var}
          fi
          exec ${lib.getExe s.wrap} "$@"
        '';
      }
    );
in
{
  sops = {
    # Relative to THIS file: the secrets file sits in nixos/.
    defaultSopsFile = ../host-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    secrets = lib.mapAttrs' (_: s: lib.nameValuePair s.secret { owner = username; }) envSecrets // {
      user_password = {
        neededForUsers = true;
      };
      root_password = {
        neededForUsers = true;
      };
      # Phone-agent bearer token, at the exact path the client reads; sops
      # re-materializes it every boot, so ~/.config needn't be persisted.
      phone_agent_token = {
        owner = username;
        path = "/home/${username}/.config/phone-agent/token";
        mode = "0400";
      };
      # restic repository password. Root-only: the backup runs as a system
      # service, and a user-readable copy would hand every snapshot to a
      # compromised session.
      restic_password = { };

      # Read from their /run/secrets paths, never exported:
      # - buttondown_*: one per newsletter (separate identities and sending
      #   reputations), scoped emails:write; newsletter.sh reads *_FILE.
      # - cloudflare_api_token: wrangler takes only the env var, so the blog
      #   Makefiles set it for that one command (its OAuth login would not
      #   survive the tmpfs root).
      # - twine_api_key: memd's release.sh reads TWINE_API_KEY_FILE.
      buttondown_api_key_hotelevangelism.owner = username;
      buttondown_api_key_volatiletestimony.owner = username;
      cloudflare_api_token.owner = username;
      twine_api_key.owner = username;
      apify_api_key.owner = username;
      gsc_service_account.owner = username;
    };
  };

  home-manager.users.${username} = {
    programs.fish.shellInit = lib.concatStrings (
      lib.mapAttrsToList (var: s: ''
        test -r ${pathOf s}; and set -gx ${var} (cat ${pathOf s})
      '') global
    );
    home.packages = lib.mapAttrsToList wrapper wrapped;
  };
}
