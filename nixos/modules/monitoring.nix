# Netdata: real-time system dashboard for the travel-bubble tablet.
# Reached at http://<bubble-ap-addr>:19999 from a bubble client, or over
# `adb reverse tcp:19999 tcp:19999` on the USB cable (loopback path).
#
# The NVIDIA go.d collector is force-disabled: it shells out to nvidia-smi on a
# loop, which wakes the dGPU and defeats RTD3 power-off (CLAUDE.md NVIDIA note).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  bubble = config.vol.travel-bubble;
  # Bubble AP address (x.y.z.1/24) → source subnet x.y.z.0/24 for the match.
  subnet =
    let
      parts = lib.splitString "/" bubble.address;
      octets = lib.splitString "." (builtins.head parts);
    in
    "${lib.concatStringsSep "." (lib.take 3 octets)}.0/${lib.last parts}";
in
{
  services.netdata = {
    enable = true;
    # Everything else auto-detects; only the GPU poller is turned off.
    configDir."go.d.conf" = pkgs.writeText "netdata-go.d.conf" ''
      modules:
        nvidia_smi: no
    '';
  };

  # Metrics DB on LUKS /persist, not the ~4 GB tmpfs root: keeps the dbengine
  # ring buffer out of RAM and preserves history across reboots. systemd's
  # StateDirectory/CacheDirectory fixes ownership (netdata:netdata) each start.
  environment.persistence."/persist".directories = [
    "/var/lib/netdata"
    "/var/cache/netdata"
  ];

  # Accept :19999 only from the bubble subnet. Scoping by source (not by the
  # wlp4s0 interface) keeps it closed when wlp4s0 is a Wi-Fi *client* on an
  # untrusted hotel network. Loopback stays open for the adb-reverse cable path.
  # The rule lands in the stock nixos-fw chain, which is reflushed on reload, so
  # no matching stop-command is needed.
  networking.firewall.extraCommands = lib.mkIf bubble.enable ''
    iptables -A nixos-fw -p tcp -s ${subnet} --dport 19999 -j nixos-fw-accept
  '';
}
