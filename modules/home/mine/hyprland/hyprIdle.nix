{ pkgs, lib, config, osConfig, ... }: with pkgs; with builtins; with lib; {
  options = {
    home.mine.idle = with types; {
      enable = mkOption {
        type = bool;
        default = osConfig.programs.hyprlock.enable;
        description = "Preconfigure hypridle for Hyprland.";
      };
      lock = mkOption {
        type = int;
        default = 2;
        description = "Idle timeout in minutes before locking the screen.";
      };
      suspend = mkOption {
        type = int;
        default = 15;
        description = "Idle timeout in minutes before suspending the system.";
      };
    };
  };

  config =
    let
      cfg = config.home.mine.idle;
      loginCtrl = "${osConfig.systemd.package}/bin/loginctl";
      hyprctl = "${if config.wayland.windowManager.hyprland.package != null then config.wayland.windowManager.hyprland.package else osConfig.programs.hyprland.package}/bin/hyprctl";
      hyprlock = "${config.programs.hyprlock.package}/bin/hyprlock";
      pidof = "${pkgs.busybox}/bin/pidof";
      brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
      systemctl = "${osConfig.systemd.package}/bin/systemctl";
      notifySend = "${pkgs.libnotify}/bin/notify-send";
    in
    {
      services.hypridle = mkIf cfg.enable {
        enable = mkDefault true;

        settings = {
          general = {
            before_sleep_cmd = "${loginCtrl} lock-session"; # lock before suspend
            after_sleep_cmd = "${hyprctl} dispatch dpms on"; # enable monitors
            lock_cmd = "${pidof} hyprlock || ${hyprlock}"; # lock only if not already locked
          };

          listener = [
            {
              # dim screen after inactivity
              timeout = cfg.lock * 60 - 10;
              on-timeout = "${brightnessctl} -s set 10";
              on-resume = "${brightnessctl} -r";
            }
            {
              # disable keyboard backlight after inactivity
              timeout = cfg.lock * 60 - 30;
              on-timeout = "${brightnessctl} -sd rgb:kbd_backlight set 0";
              on-resume = "${brightnessctl} -rd rgb:kbd_backlight";
            }

            {
              # notify user
              timeout = cfg.lock * 60 - 30;
              on-timeout = "${notifySend} -e -t 5000 'Locking screen in 10sec'";
            }
            {
              # lock screen
              timeout = cfg.lock * 60;
              on-timeout = "${loginCtrl} lock-session";
            }
            {
              # turn off monitors
              timeout = cfg.lock * 60 + 20;
              on-timeout = "${hyprctl} dispatch dpms off";
              on-resume = "${hyprctl} dispatch dpms on && ${brightnessctl} -r";
            }
            {
              # suspend system
              timeout = cfg.suspend * 60;
              on-timeout = "${systemctl} suspend";
            }
          ];
        };
      };
    };
}
