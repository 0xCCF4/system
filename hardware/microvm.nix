{ lib
, hostConfig
, vmName
, config
, ...
}:
with lib;
{
  imports = [ ../nixos/caddy_hide_server.nix ];

  config = {
    system.stateVersion = hostConfig.system.stateVersion;
    networking.hostName = "vm-${vmName}";

    microvm.hypervisor = mkDefault "qemu";

    microvm.shares = [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        readOnly = true;
        proto = "virtiofs";
      }
    ];
  };
}
