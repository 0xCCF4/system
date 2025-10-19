{ inputs
, pkgs
, lib
, config
, nixos-hardware
, ...
}:
with lib;
{
  config = {
    boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sr_mod" "virtio_blk" ];
  };

}
