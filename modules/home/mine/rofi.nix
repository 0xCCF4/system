{ config
, pkgs
, lib
, osConfig
, mine
, ...
}:
with lib; with builtins;
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
          /* adapted from https://github.com/nix-community/stylix/blob/master/modules/rofi/hm.nix */
          inherit (config.lib.formats.rasi) mkLiteral;
          mkRgba = opacity: color:
            let
              r = config.lib.stylix.colors."${color}-rgb-r";
              g = config.lib.stylix.colors."${color}-rgb-g";
              b = config.lib.stylix.colors."${color}-rgb-b";
            in
            mkLiteral "rgba ( ${r}, ${g}, ${b}, ${opacity} % )";
          mkRgb = mkRgba "100";
          rofiOpacity = toString (builtins.ceil (config.stylix.opacity.popups * 100));
          /* end from */
        in
        {
          "*" = {
            "font" = "${config.stylix.fonts.monospace.name}, FiraCode Nerd Font 15";
          };

          "window" = {
            "background-color" = mkLiteral "@background";
            "border-color" = mkRgba rofiOpacity "base0D";
            "border-width" = "${toString config.wayland.windowManager.hyprland.settings.general.border_size}px";
            "border" = mkLiteral "2";
          };

          "element-icon" = { };

          "element-icon selected" = {
            "background-color" = mkLiteral "@active-background";
          };
        };
    };
  };
}
