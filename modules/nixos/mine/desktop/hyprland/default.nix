{ lib, config, ... }: with lib; {
  options.mine.desktop.hyprland = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable Hyprland desktop environment.";
    };
  };

  config = mkIf config.mine.desktop.hyprland.enable {
    programs.hyprland.enable = true;
    programs.hyprlock.enable = true;
  };
}
