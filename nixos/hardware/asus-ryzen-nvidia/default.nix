{ ... }: {
  imports = [
    ./gpu.nix
    ./kernel.nix
    ./keyboard-rgb.nix
  ];

  # mode 1 at the slowest of the three speeds: one colour swelling in and
  # out. `colour-cycle` (mode 2) is the only other real effect this EC has.
  hardware.asus.keyboardRgb = {
    enable = true;
    mode = "breathe";
    speed = "low";
  };
}
