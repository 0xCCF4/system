{ pkgs, lib, config, osConfig, ... }: with pkgs; with builtins; with lib; {
  config = {
    programs.hyprlock = {
      enable = mkDefault osConfig.programs.hyprlock.enable;

      package = mkDefault osConfig.programs.hyprlock.package;
    };
  };
}
