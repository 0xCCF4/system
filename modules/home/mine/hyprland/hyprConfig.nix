{ pkgs, lib, config, ... }: with pkgs; with builtins; with lib; let
  waybar = "${config.programs.waybar.package}/bin/waybar";
  terminal = "${config.programs.kitty.package}/bin/kitty";
  fileManager = "nautilus";
  rofi = "${config.programs.rofi.package}/bin/rofi";
  snip = "${config.services.flameshot.package}/bin/flameshot";
  lock = "${config.programs.hyprlock.package}/bin/hyprlock";
in
{
  wayland.windowManager.hyprland = {
    settings = {
      "$terminal" = "${terminal}";
      "$fileManager" = "${fileManager}";
      "$menu" = "${rofi} -show drun";
      "$reload_waybar" = "pkill waybar; ${waybar} &";
      "$snip" = "${snip}";
      "$lock" = "${lock}";

      input = {
        kb_layout = "de";

        touchpad = {
          natural_scroll = mkDefault true;
        };
      };

      general = {
        border_size = 2;
        gaps_in = 2;
        gaps_out = 1;
      };

      #animations = { #todo change
      #  # enabled = true;
      #  bezier = [ "myBezier, 0.05, 0.9, 0.1, 1.05" ];
      #  animation = [
      #    "windows, 1, 7, myBezier"
      #    "windowsOut, 1, 7, default, popin 80%"
      #    "border, 1, 10, default"
      #    "borderangle, 1, 8, default"
      #    "fade, 1, 7, default"
      #    "workspaces, 1, 6, default"
      #  ];
      #};

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      cursor = {
        inactive_timeout = 30;
      };

      animations.enabled = false;
      decoration.blur.enabled = false;
      decoration.shadow.enabled = false;

      env = [
        "GTK_THEME,Tokyo-Night-Dark"
        "GTK_ICON_THEME,Adwaita"
        "XCURSOR_THEME,Adwaita"

        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
      ];

      "$mainMod" = "SUPER";

      bind = [
        # Main binds
        "$mainMod, Return, exec, $terminal"
        "$mainMod, Q, killactive,"
        "$mainMod SHIFT, Q, forcekillactive,"
        "$mainMod, M, exit,"
        "$mainMod, E, exec, $fileManager"
        "$mainMod, V, togglefloating,"
        "$mainMod, D, exec, $menu"
        "$mainMod, R, exec, $reload_waybar"
        "$mainMod, R, exec, hyprctl reload"
        "$mainMod, S, exec, $snip"
        "$mainMod, L, exec, $lock"
        "$mainMod SHIFT, L, exec, systemctl suspend"

        # Move focus
        "$mainMod, l, movefocus, l"
        "$mainMod, h, movefocus, r"
        "$mainMod, k, movefocus, u"
        "$mainMod, j, movefocus, d"

        # Workspaces
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod, 0, workspace, 10"

        # Move windows between workspaces
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod SHIFT, 0, movetoworkspace, 10"

        # Scroll between workspaces
        "$mainMod, mouse_down, workspace, e+1"
        "$mainMod, mouse_up, workspace, e-1"

        "$mainMod, Backspace, submap, clean"
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      bindl = [
        "ALT, Shift_L, exec, hyprctl switchxkblayout main next"
      ];

      ##############################
      ### WINDOWS AND WORKSPACES ###
      ##############################
      windowrulev2 = [
        "suppressevent maximize, class:.*"
      ];
    };

    submaps = {
      clean.settings = {
        bind = [
          "$mainMod, Backspace, submap, reset"
        ];
      };
    };
  };
}
