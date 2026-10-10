# Phone Agent Setup

## Prerequisites
1. Install Termux + Termux:API + Shizuku on the S26 Ultra
2. Join both devices to the same Tailscale network
3. Build the phone MCP server on-device with Claude Code — see
   phoneAgentBuild/phone/PHONE-ENV.md (the phone repo is built there, not
   rsynced from the laptop)

## Laptop Setup (NixOS)
1. The module is imported by nixos/hosts/volnix.nix; set there:
     phone-agent.enable = true;
     phone-agent.phoneTailscaleIP = "100.x.y.z";   # from Tailscale Android app
     phone-agent.tokenFile = config.sops.secrets."phone-agent-token".path;
   The token value must match ~/.config/phone-agent/token on the phone.
2. Rebuild: make switch
3. Test: phone-agent phone.system.ping

## Testing the connection
    curl -sf http://<phoneTailscaleIP>:8462/health
    phone-agent phone.sensor.read_imu
