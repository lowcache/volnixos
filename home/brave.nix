{ config, pkgs, lib, ... }: {
  programs.chromium = {
    enable = true;
    package = pkgs.brave;
    commandLineArgs = [
      "--ozone-platform-hint=auto"
      "--disable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoEncoder"
      "--disable-gpu-memory-buffer-video-frames"
      "--enable-features=TouchpadOverscrollHistoryNavigation"
    ];
  };
}
