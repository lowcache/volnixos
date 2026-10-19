# Google Drive from the terminal: a fixed verb set over rclone (`gd help`).
# fuse is left out on purpose: `gd mount` needs NixOS's setuid fusermount3 wrapper.
{
  writeShellApplication,
  coreutils,
  fzf,
  gnugrep,
  jq,
  rclone,
}:
writeShellApplication {
  name = "gd";
  runtimeInputs = [
    coreutils
    fzf
    gnugrep
    jq
    rclone
  ];
  text = builtins.readFile ./gd.sh;
}
