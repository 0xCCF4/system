{ config
, pkgs
, lib
, osConfig
, mine
, ...
}:
with lib;
{
  config = {
    programs.rofi = {
      enable = mkDefault ((mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false) && (osConfig.programs.hyprland.enable || config.wayland.windowManager.hyprland.enable));
      extraConfig = {
        modi = [ "drun" "window" "run" ];
        icon-theme = "Papirus-Dark";
        show-icons = true;
        terminal = "${config.programs.kitty.package}/bin/kitty";
        drun-display-format = "{icon} {name}";
        location = 0;
        disable-history = false;
        sidebar-mode = false;
        display-drun = " ";
        display-run = " ";
        display-window = " ";

        kb-row-up = "Up,Control+k";
        kb-row-left = "Left,Control+h";
        kb-row-right = "Right,Control+l";
        kb-row-down = "Down,Control+j";

        kb-accept-entry = "Control+z,Control+y,Return,KP_Enter";

        kb-remove-to-eol = "";
        kb-move-char-back = "Control+b";
        kb-remove-char-back = "BackSpace";
        kb-move-char-forward = "Control+f";
        kb-mode-complete = "Control+o";
      };
      theme =
        let
          inherit (config.lib.formats.rasi) mkLiteral;
        in
        {
          "element-icon" = { };

          "element-icon selected" = {
            "background-color" = mkLiteral "@active-background";
          };
        };
    };
  };
}
