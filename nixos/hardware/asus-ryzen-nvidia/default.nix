{ ... }: {
  imports = [
    ./gpu.nix
    ./kernel.nix
    ./keyboard-rgb.nix
  ];

  # colour-cycle is mode 2: the whole board walks the hue together. This is
  # the effect asusctl silently refused to deliver.
  hardware.asus.keyboardRgb = {
    enable = true;
    mode = "colour-cycle";
  };
}
