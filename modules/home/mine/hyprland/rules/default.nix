{ config, lib, osConfig, noxa, pkgs, ... }: with lib; with builtins; {
  imports = noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    windowrule = [
      {
        name = "suppress-maximize";
        "match:class" = ".*";

        suppress_event = [ "maximize" ];
      }
      {
        name = "pinned-border-size";
        "match:pin" = 1;
        border_size = 10;
      }
    ];
  };
}
