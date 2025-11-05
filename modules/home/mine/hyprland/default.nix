{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  imports = noxa.lib.nixDirectoryToList ./.;

  config = mkIf osConfig.programs.hyprland.enable {
    programs.kitty.enable = mkDefault true;

    wayland.windowManager.hyprland = {
      enable = mkDefault true;
      # set the Hyprland and XDPH packages to null to use the ones from the NixOS module
      package = null;
      portalPackage = null;
    };

    home.sessionVariables.NIXOS_OZONE_WL = "1";

    services.hyprpolkitagent.enable = mkDefault true;

    home.packages = with pkgs; [
      hyprpicker
      hyprsysteminfo
      grim
      slurp
      wl-clipboard
    ];
  };

}
