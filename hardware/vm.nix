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
    (import ./disko-server.nix {
      device = "/dev/sda";
      bootType = "bios";
      espSize = "1G";
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

  security.sudo.wheelNeedsPassword = mkDefault false; # Don't ask for passwords
  services.openssh = {
    enable = mkDefault true;
    settings.PasswordAuthentication = mkDefault false;
    settings.KbdInteractiveAuthentication = mkDefault false;
  };

  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
}
