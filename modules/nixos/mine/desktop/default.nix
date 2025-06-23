{ config, lib, ... }: with lib; {
  options.mine.desktop = with types; {
    presets = mkOption {
      type = nullOr (enum [ "gnome" "hyprland" ]);
      default = if config.mine.presets.isWorkstation then "gnome" else null;
      description = "The desktop environment to use.";
    };
    # darkMode = mkOption {
    #     type = enum [ "dark" "light" ];
    #     default = "dark";
    #     description = "The default color mode dark/light.";
    # };
  };

  imports = [
    ../../presets.nix
    ./gnome/default.nix
    ./hyprland/default.nix
  ];

  config = {
    mine.desktop.hyprland.enable = mkIf (config.mine.desktop.presets == "hyprland") true;
    mine.desktop.gnome.enable = mkIf (config.mine.desktop.presets == "gnome") true;

    # mine.desktop.gnome.darkMode = mkDefault config.mine.desktop.darkMode;
    # mine.desktop.hyprland.darkMode = mkDefault config.mine.desktop.darkMode;
  };
}
