{ ... }: {
  imports = [
    ./gpu.nix
    ./kernel.nix
    ./keyboard-rgb.nix
  ];

  # mode 3. It fires on this controller but what it actually renders was
  # never pinned down -- swap to colour-cycle (mode 2, whole board walking
  # the hue together) if it disappoints.
  hardware.asus.keyboardRgb = {
    enable = true;
    mode = "rainbow";
    speed = "high";
  };
}
