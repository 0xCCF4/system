{ lib, ... }: with lib; {
  # Bootloader configuration
  boot.loader.grub = {
    enable = mkDefault false;
    zfsSupport = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    mirroredBoots = [
      { devices = [ "nodev" ]; path = "/boot"; }
    ];
  };
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.systemd-boot.enable = mkDefault true;
}
