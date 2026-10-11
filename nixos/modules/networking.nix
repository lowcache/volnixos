# NetworkManager for the physical interfaces. The VM taps are systemd-networkd's
# (vms.nix, anonymous-mode/guests.nix), and NetworkManager is told to ignore them.
{
  networking.networkmanager = {
    enable = true;
    wifi = {
      scanRandMacAddress = true;
      macAddress = "stable-ssid";
    };
    settings = {
      "connection-tether-lowprio" = {
        match-device = "driver:rndis_host,driver:cdc_ether,driver:cdc_ncm";
        "ipv4.route-metric" = 700;
      };
    };
  };
}
