{ lib
, options
, config
, ...
}:
with lib;
{
  # Every microVM (mine.microvm.names) runs its own kernel: it gets the kernel hardening of
  # the fleet (nixos/kernel_hardening.nix) with the server defaults; the hardware parts
  # (IOMMU, USBGuard) live in the hardware files and do not apply.
  config = optionalAttrs (options ? microvm) {
    microvm.vms = genAttrs config.mine.microvm.names (_: {
      config.imports = [
        ../presets.nix
        ../kernel_hardening.nix
      ];
    });
  };
}
