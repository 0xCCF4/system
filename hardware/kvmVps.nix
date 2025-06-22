{ inputs
, pkgs
, lib
, config
, modulesPath
, disko
, ...
}:
with lib;
{
  imports = [
    disko.nixosModules.disko
    (import ./disks/disko-server.nix {
      device = "/dev/vda";
      bootType = "bios";
      swapSize = "8G";
    })
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.grub.enable = mkDefault true; # Use the boot drive for GRUB
  #boot.loader.grub.device = "/dev/sda";
  boot.growPartition = mkDefault true;
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sr_mod" "virtio_blk" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  services.qemuGuest.enable = mkDefault true;

  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
}
