# Nix daemon settings (Lix from nixpkgs), substituters, GC, and the nixpkgs
# config block.
{
  pkgs,
  username,
  ...
}:
{
  nix = {
    # Lix from nixpkgs (binary-cached, tracks nixpkgs updates). Replaces the
    # lix-project/nixos-module flake input, whose release branches lag behind
    # the lixPackageSets versions nixpkgs keeps around.
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        username
      ];
      # Own cache first: every miss elsewhere costs a round-trip, so query
      # volnixos before falling through to upstreams. Populated by CI
      # (.github/workflows/build.yml); key is public by design.
      substituters = [
        "https://volnixos.cachix.org"
        "https://nix-community.cachix.org"
        "https://cache.lix.systems"
        # cuda-maintainers.cachix.org removed 2026-09-17: the cache now answers
        # 401 ("doesn't exist or you're not authorized") on nix-cache-info, so
        # Lix rejected it as "not a binary cache" and warned on every command.
        # Nothing was being substituted from it. Re-add the URL and its key
        # together if it goes public again.
        "https://cache.numtide.com"
        "https://attic.xuyh0120.win/lantian"
      ];
      trusted-public-keys = [
        "volnixos.cachix.org-1:GUKpgN2Tzh67uYZtUaEsFr1U7UVLrFG1iCoF860CY5Y="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.lix.systems:aBnZU3F19808R5N0sczBmsWwI5YI+433R9M2iS2Hcy4="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      ];
      min-free = 536870912; # 512MB
      max-free = 1073741824; # 1GB
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 5d";
    };
    optimise.automatic = true;
  };

  nixpkgs = {
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
      permittedInsecurePackages = [
        "pulsar-1.132.1"
      ];
    };
  };
}
