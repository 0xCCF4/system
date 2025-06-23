{ inputs
, pkgs
, lib
, config
, ...
}:
with lib; with builtins;
{
  imports = [
    ./presets.nix
    ./unfree.nix
  ];

  options.mine.virtualization = with types;
    let
      presets = config.mine.presets;
    in
    {
      virtualBox = mkOption {
        type = bool;
        default = false;
        description = "Enable VirtualBox support.";
      };
      virtualBoxUsers = mkOption {
        type = listOf str;
        default = [ ];
        description = "Users that should be added to the vboxusers group.";
      };
      virtualBoxExtensionPack = mkOption {
        type = bool;
        default = true;
        description = "Enable VirtualBox Extension Pack support.";
      };
      distrobox = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Distrobox support.";
      };
      flatpak = mkOption {
        type = bool;
        default = presets.isWorkstation;
        description = "Enable Flatpak support.";
      };
    };

  config =
    let
      cfg = config.mine.virtualization;

      flatpak = cfg.flatpak || cfg.distrobox;
    in
    {
      virtualisation.virtualbox.host.enable = mkDefault cfg.virtualBox;
      virtualisation.virtualbox.host.enableExtensionPack = mkDefault cfg.virtualBoxExtensionPack;
      users.extraGroups.vboxusers.members = cfg.virtualBoxUsers;

      services.flatpak.enable = mkDefault flatpak;

      virtualisation.podman.enable = mkDefault cfg.distrobox;
      virtualisation.podman.dockerCompat = mkDefault cfg.distrobox;
      environment.systemPackages =
        [ ]
        ++ lists.optionals cfg.distrobox [
          pkgs.distrobox
          pkgs.podman-compose
        ]
        ++ lists.optionals cfg.flatpak [
          pkgs.flatpak
          pkgs.flatpak-builder
        ];

      mine.unfree.allowList = mkIf (cfg.virtualBox && cfg.virtualBoxExtensionPack) [ "Oracle_VirtualBox_Extension_Pack" ];
    };
}
