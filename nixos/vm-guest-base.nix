# Shared by every MicroVM guest (nixos/vms.nix, modules/anonymous-mode/guests.nix).
inputs: {
  _module.args.inputs = inputs;
  imports = [ inputs.microvm.nixosModules.microvm ];
  # Trust the CPU RNG so early boot (vsock, tor) isn't starved of entropy.
  boot.kernelParams = [ "random.trust_cpu=on" ];
  networking = {
    useNetworkd = true;
    firewall.enable = true;
  };
  systemd.network.enable = true;
  microvm.hypervisor = "cloud-hypervisor";
  system.stateVersion = "24.11";
}
