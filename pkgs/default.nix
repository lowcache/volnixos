# Repo-local packages, added under new names so nothing upstream is overridden.
final: _prev: {
  tweakcc = final.callPackage ./tweakcc/package.nix { };
  claude-code-tweaked = final.callPackage ./claude-code-tweaked/package.nix { };
}
