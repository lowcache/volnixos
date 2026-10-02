# Docker, the fooocus OCI container, and Waydroid.
{
  username,
  ...
}:
{
  virtualisation = {
    docker = {
      enable = true;
      autoPrune.enable = true;
      liveRestore = false;
    };
    oci-containers = {
      backend = "docker";
      containers = {
        "fooocus" = {
          # Pinned by digest (was :latest). Bump: docker pull ghcr.io/lllyasviel/fooocus:latest
          # then copy the RepoDigest from `docker image inspect`.
          image = "ghcr.io/lllyasviel/fooocus@sha256:a1c3251054a38c22f783b680600050bedf7fe547d0239a8d772d0d372a98a5ce";
          autoStart = false;
          # Loopback only: a published port bypasses the NixOS firewall.
          ports = [ "127.0.0.1:7865:7865" ];
          volumes = [ "/home/${username}/Storage/ai-generation/fooocus:/content/data" ];
          environment = {
            CMDARGS = "--listen";
            DATADIR = "/content/data";
            config_path = "/content/data/config.txt";
            path_checkpoints = "/content/data/models/checkpoints/";
            path_loras = "/content/data/models/loras/";
            path_outputs = "/content/data/outputs/";
          };
          extraOptions = [
            "--device"
            "nvidia.com/gpu=0"
          ];
        };
      };
    };
    waydroid.enable = true;
  };
}
