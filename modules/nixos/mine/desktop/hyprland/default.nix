{ lib, ... }: with lib; {
  options.mine.desktop.hyprland = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable Hyprland desktop environment.";
    };

    # todo: copy configs to here
  };
}
