{ inputs
, pkgs
, lib
, config
, modulesPath
, ...
}:
with lib;
{
  imports = [
    "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.networkmanager.enable = true;
  networking.wireless.enable = false;

  boot.swraid.enable = true;
  boot.swraid.mdadmConf = "PROGRAM /usr/bin/env true";
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = [ pkgs.mesa ];
  services.lvm.enable = true;
  services.lvm.boot.thin.enable = true;

  nixpkgs.hostPlatform = mkDefault "x86_64-linux";
}
