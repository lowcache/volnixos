# Travel bubble: when the laptop is cabled to the Panhandler (Pi travel router), its Wi-Fi
# radio becomes an AP for the other devices (Roku, phones). Clients → wlp4s0 (AP) → NAT →
# enp3s0 → Pi (adblock DNS, tailnet, captive-portal handling) → hotel uplink.
#
# Machine values (interfaces, Pi address) live in ../hosts/<name>.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.vol.travel-bubble;
  profile = "vol-bubble";
  nmcli = "${config.networking.networkmanager.package}/bin/nmcli";
  systemctl = "${config.systemd.package}/bin/systemctl";
  # Network address of cfg.address (x.y.z.1/24 → x.y.z.0/24).
  subnet =
    let
      parts = lib.splitString "/" cfg.address;
      octets = lib.splitString "." (builtins.head parts);
    in
    "${lib.concatStringsSep "." (lib.take 3 octets)}.0/${lib.last parts}";
in
{
  options.vol.travel-bubble = {
    enable = lib.mkEnableOption "Wi-Fi AP for other devices while cabled to the Panhandler";
    apInterface = lib.mkOption {
      type = lib.types.str;
      description = "Wi-Fi interface that becomes the AP.";
    };
    uplinkInterface = lib.mkOption {
      type = lib.types.str;
      description = "Wired interface cabled to the Pi.";
    };
    piAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.73.0.1";
      description = "The Pi's downlink address: its DHCP server identifier and blocky DNS.";
    };
    address = lib.mkOption {
      type = lib.types.str;
      default = "10.74.0.1/24";
      description = "AP address/prefix (a /24); NM shared mode serves DHCP from it.";
    };
    band = lib.mkOption {
      type = lib.types.enum [
        "a"
        "bg"
      ];
      default = "a";
      description = "5 GHz (a) keeps the AP off the Pi's 2.4 GHz uplink airtime.";
    };
    webuiMacs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Bubble client MACs allowed to the Pi's web UI (port 8080), e.g. the phone, so it can run
        captive-portal recovery. Everything else on the bubble stays DNS-only to the Pi.
      '';
    };
    channel = lib.mkOption {
      type = lib.types.ints.positive;
      default = 36;
    };
    country = lib.mkOption {
      type = lib.types.str;
      default = "US";
      description = ''
        Regulatory domain. cfg80211 otherwise sits at WORLD (00), learns a country only from the
        AP it is associated to, and falls back to WORLD on disconnect, where 5 GHz is no-IR and
        the AP fails to start ("Failed to start AP functionality").
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # SSID + PSK stay out of the store: rendered by sops, substituted by ensureProfiles.
    sops = {
      secrets.bubble_ssid = { };
      secrets.bubble_psk = { };
      templates."vol-bubble.env".content = ''
        bubble_ssid=${config.sops.placeholder.bubble_ssid}
        bubble_psk=${config.sops.placeholder.bubble_psk}
      '';
    };

    boot.extraModprobeConfig = ''options cfg80211 ieee80211_regdom="${cfg.country}"'';

    # Clients resolve through the Pi's blocky (adblock + DoH), not the laptop's resolver.
    environment.etc."NetworkManager/dnsmasq-shared.d/vol-bubble.conf".text = ''
      dhcp-option=option:dns-server,${cfg.piAddress}
    '';

    # Holds the AP up and the lid/sleep inhibited for exactly as long as the bubble lives.
    systemd.services.vol-bubble = {
      description = "Travel bubble: Wi-Fi AP via the Panhandler";
      after = [ "NetworkManager.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          # User hint: survives cfg80211's restore-to-WORLD when the STA link drops.
          "${pkgs.iw}/bin/iw reg set ${cfg.country}"
          "${nmcli} --wait 45 connection up ${profile}"
        ];
        ExecStart = "${config.systemd.package}/bin/systemd-inhibit --what=handle-lid-switch:sleep:idle --who=vol-bubble --why='Travel bubble AP is serving devices' ${pkgs.coreutils}/bin/sleep infinity";
        ExecStopPost = "-${nmcli} connection down ${profile}";
      };
    };

    networking = {
      networkmanager = {
        ensureProfiles = {
          environmentFiles = [ config.sops.templates."vol-bubble.env".path ];
          profiles.${profile} = {
            connection = {
              id = profile;
              type = "wifi";
              interface-name = cfg.apInterface;
              # Driven by the dispatcher below, never by NM autoconnect.
              autoconnect = false;
            };
            wifi = {
              mode = "ap";
              ssid = "$bubble_ssid";
              inherit (cfg) band channel;
            };
            wifi-security = {
              key-mgmt = "wpa-psk";
              proto = "rsn";
              pairwise = "ccmp";
              group = "ccmp";
              psk = "$bubble_psk";
            };
            ipv4 = {
              method = "shared";
              address1 = cfg.address;
            };
            ipv6.method = "disabled";
          };
        };

        # Bubble up when the cable leases from the Pi (server id = piAddress), down when it drops.
        dispatcherScripts = [
          {
            source = pkgs.writeShellScript "vol-bubble-dispatch" ''
              [ "$1" = "${cfg.uplinkInterface}" ] || exit 0
              case "$2" in
                up | dhcp4-change)
                  if [ "''${DHCP4_DHCP_SERVER_IDENTIFIER:-}" = "${cfg.piAddress}" ]; then
                    ${systemctl} start --no-block vol-bubble.service
                  fi
                  ;;
                down | pre-down)
                  ${systemctl} stop --no-block vol-bubble.service
                  ;;
              esac
            '';
          }
        ];
      };

      firewall = {
        # From the bubble the laptop answers only DHCP and DNS (NM's shared dnsmasq).
        interfaces.${cfg.apInterface} = {
          allowedUDPPorts = [
            53
            67
          ];
          allowedTCPPorts = [ 53 ];
        };
        # Forwarding, matched on the bubble subnet so VM/tether traffic over wlp4s0 as a client is
        # untouched: bubble → Pi cable only, plus replies; never the tether, VMs or Docker, and
        # fail-closed without the cable. To the Pi itself only DNS, plus the web UI for webuiMacs:
        # its webui/SSH trust the cable subnet, and bubble clients arrive masqueraded as the laptop.
        # Own chain in FORWARD, so it holds whether Docker (FORWARD policy DROP) starts before or after.
        extraCommands = ''
          iptables -N vol-bubble-fwd 2>/dev/null || iptables -F vol-bubble-fwd
          iptables -A vol-bubble-fwd -s ${subnet} -d ${cfg.piAddress} -p udp --dport 53 -j ACCEPT
          iptables -A vol-bubble-fwd -s ${subnet} -d ${cfg.piAddress} -p tcp --dport 53 -j ACCEPT
          ${
            lib.concatMapStrings (mac: ''
              iptables -A vol-bubble-fwd -s ${subnet} -d ${cfg.piAddress} -p tcp --dport 8080 -m mac --mac-source ${mac} -j ACCEPT
            '') cfg.webuiMacs
          }iptables -A vol-bubble-fwd -s ${subnet} -d ${cfg.piAddress} -j DROP
          iptables -A vol-bubble-fwd -s ${subnet} -i ${cfg.apInterface} -o ${cfg.uplinkInterface} -j ACCEPT
          iptables -A vol-bubble-fwd -d ${subnet} -i ${cfg.uplinkInterface} -o ${cfg.apInterface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
          iptables -A vol-bubble-fwd -s ${subnet} -j DROP
          iptables -A vol-bubble-fwd -d ${subnet} -j DROP
          iptables -C FORWARD -j vol-bubble-fwd 2>/dev/null || iptables -I FORWARD -j vol-bubble-fwd
        '';
        extraStopCommands = ''
          iptables -D FORWARD -j vol-bubble-fwd 2>/dev/null || true
          iptables -F vol-bubble-fwd 2>/dev/null || true
          iptables -X vol-bubble-fwd 2>/dev/null || true
        '';
      };
    };
  };
}
