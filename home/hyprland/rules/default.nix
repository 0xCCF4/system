{ config
, lib
, osConfig
, inputs
, pkgs
, ...
}:
with lib;
with builtins;
{
  imports = inputs.noxa.lib.nixDirectoryToList ./.;

  wayland.windowManager.hyprland.settings = {
    window_rule = [
      {
        name = "suppress-maximize";
        match.class = ".*";

        suppress_event = "maximize";
      }
      {
        name = "pinned-border-size";
        match.pin = true;
        border_size = 10;
      }
      # fix jetbrains windows suppress.focus.stealing=false
      {
        name = "noinitialfocus-toolbox";
        no_initial_focus = true;
        match.class = "jetbrains-toolbox";
      }
      {
        name = "noinitialfocus-jetbrains";
        no_initial_focus = true;
        match.class = "(jetbrains-)(.*)";
      }
      {
        name = "noinitialfocus-jetbrains-win";
        no_initial_focus = true;
        match.class = "(jetbrains-) (.*)";
        match.title = "^win(.*)";
        match.initial_title = "win.*";
        no_focus = true;
        focus_on_activate = false;
        no_follow_mouse = true;
        suppress_event = "activatefocus";
      }
    ];
  };
}
