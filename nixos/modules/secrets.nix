# Host secrets, sops-managed. Age key = the persisted host SSH key
# (/persist/etc/ssh/ssh_host_ed25519_key). File layout and trust boundaries:
# see nixos/.sops.yaml — host-secrets.yaml is encrypted to admin + host key;
# vm-secrets.yaml (used by net-gate) to the host key ONLY.
{
  username,
  ...
}:
{
  sops = {
    # NOTE: relative to THIS file — the secret lives one level up, next to
    # hardware-configuration.nix in nixos/.
    defaultSopsFile = ../host-secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      user_password = {
        neededForUsers = true;
      };
      root_password = {
        neededForUsers = true;
      };
      gemini_api_key = {
        owner = username;
      };
      gh_token = {
        owner = username;
      };
      # Buttondown API tokens, one per newsletter account — the two lists are
      # deliberately separate identities, so a single shared key would defeat
      # the separation at the only layer that still enforces it. Scoped in
      # Buttondown to emails:write / subscribers:none; ./newsletter.sh in each
      # blog repo only ever creates drafts, and a key that can also read the
      # subscriber list is a bigger blast radius than the script needs.
      #
      # Consumed by PATH (/run/secrets/...), never exported: the scripts read
      # BUTTONDOWN_API_KEY_FILE so the token stays out of the environment.
      buttondown_api_key_hotelevangelism = {
        owner = username;
      };
      # Cloudflare deploy token for `make deploy` in the blog repos. Needed
      # because wrangler stores its OAuth credentials under ~/.config/.wrangler,
      # which impermanence discards on every boot (home/persist.nix does not
      # list it), so an interactive `wrangler login` survives exactly until the
      # next reboot. A sops secret survives by construction rather than by
      # remembering to persist a directory.
      #
      # wrangler reads CLOUDFLARE_API_TOKEN from the environment and offers no
      # file-based alternative, so the blog Makefiles cat this path into the
      # environment of that one command rather than exporting it into the shell.
      cloudflare_api_token = {
        owner = username;
      };
      # Second Buttondown token, for Volatile Testimony. Separate from the
      # hotelevangelism key on purpose: the two lists are separate identities
      # with separate sending reputations, and one shared key would undo that
      # at the only layer still enforcing it.
      buttondown_api_key_volatiletestimony = {
        owner = username;
      };
      # Phone-agent bearer token (laptop -> phone MCP auth, scripts/verify.sh).
      # Placed at the exact path the client reads; sops re-materializes it at
      # activation every boot, so it survives the impermanence rollback of
      # ~/.config (which is not a persisted path — see home/persist.nix).
      phone_agent_token = {
        owner = username;
        path = "/home/${username}/.config/phone-agent/token";
        mode = "0400";
      };
      # restic repository password for the external backup drive. Root-owned:
      # the backup runs as a system service, and a user-readable copy would put
      # the key to every snapshot behind the same session that gets compromised.
      restic_password = { };
      apify_api_key = {
        owner = username;
      };
      gsc_service_account = {
        owner = username;
      };
      openrouter_api_key = {
        owner = username;
      };
      twine_api_key = {
        owner = username;
      };
    };
  };
}
