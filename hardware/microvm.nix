{ lib
, hostConfig
, vmName
, config
, ...
}:
with lib;
{
  config = {
    system.stateVersion = hostConfig.system.stateVersion;
    networking.hostName = "vm-${vmName}";

    networking.enableIPv6 = false;

    microvm.hypervisor = mkDefault "qemu";

    microvm.shares = [{
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      readOnly = true;
      proto = "virtiofs";
    }];
  };
}
