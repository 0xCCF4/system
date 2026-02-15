{ config, lib, osConfig, inputs, pkgs, ... }: with lib; with builtins; {
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  config = mkIf osConfig.programs.hyprland.enable {
    programs.kitty.enable = mkDefault true;
    programs.kitty.settings = {
      scrollback_pager =
        if config.programs.helix.enable then
          "bash -c \"${getExe' pkgs.colorized-logs "ansi2txt"} | ${getExe config.programs.helix.package}\""
        else
          "${getExe pkgs.less} --chop-long-lines --RAW-CONTROL-CHARS -N";
    };

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
