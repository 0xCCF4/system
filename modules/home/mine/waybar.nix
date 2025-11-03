{ config
, pkgs
, lib
, mine
, osConfig
, ...
}:
# Originally from https://github.com/vimjoyer/nixconf Licensed under the MIT License.
with lib;
let
  pamixer = "${pkgs.pamixer}/bin/pamixer";
  pavucontrol = "${pkgs.pavucontrol}/bin/pavucontrol";
  hyprctl = "${if config.wayland.windowManager.hyprland.package != null then config.wayland.windowManager.hyprland.package else osConfig.programs.hyprland.package}/bin/hyprctl";
in
{
  config =
    let
      submapScript = pkgs.writeShellScriptBin "submap-status" ''
        handle() {
          case $1 in
            submap*) echo ''${1#*>>} ;;
          esac
        }

        ${hyprctl} submap | tr -d '\n\r'
        echo ""
        
        ${pkgs.socat}/bin/socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read -r line; do handle "$line"; done
      '';

      workspaces = {
        format = "{name} {icon}";
        format-icons = {
          active = "";
          empty = "";
          default = "";
          urgent = "";
          special = "";
        };
        on-click = "activate";
        # persistent_workspaces = { "*" = 10; };
      };
    in
    {
      home.packages = [ pkgs.playerctl ];

      programs.waybar = with config.lib.stylix.colors; {
        enable = mkDefault ((mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false) && (osConfig.programs.hyprland.enable || config.wayland.windowManager.hyprland.enable));

        settings = {
          mainBar = {
            mod = "dock";
            layer = "top";
            gtk-layer-shell = true;
            height = 14;
            position = "top";

            modules-left = [
              "custom/logo"
              "hyprland/workspaces"
              "custom/submap"
            ];
            modules-center = [
              "mpris"
            ];
            modules-right = [
              "hyprland/language"
              # "cpu"
              # "memory"
              "network"
              "bluetooth"
              "pulseaudio"
              "pulseaudio#microphone"
              "battery"
              "idle_inhibitor"
              "clock"
              "tray"
            ];

            "wlr/workspaces" = workspaces;
            "hyprland/workspaces" = workspaces;

            bluetooth = {
              format = "";
              format-connected = " {num_connections}";
              format-disabled = "";
              tooltip-format = " {device_alias}";
              tooltip-format-connected = "{device_enumerate}";
              tooltip-format-enumerate-connected = " {device_alias}";
            };

            mpris = {
              format = "{player_icon} {dynamic}";
              format-paused = "{status_icon} {dynamic}";
              player-icons = {
                "default" = "󰐊";
                "mpv" = "󰝚";
                "ncspot" = "󰝚";
              };
              status-icons = {
                "paused" = "󰏤";
              };
              # "ignored-players": ["firefox"]
            };

            clock = {
              actions = {
                on-click-backward = "tz_down";
                on-click-forward = "tz_up";
                on-click-right = "mode";
                on-scroll-down = "shift_down";
                on-scroll-up = "shift_up";
              };
              calendar = {
                format = {
                  days = "<span color='#${base04-hex}'><b>{}</b></span>";
                  months = "<span color='#${base09-hex}'><b>{}</b></span>";
                  today = "<span color='#${base08-hex}'><b><u>{}</u></b></span>";
                  weekdays = "<span color='#${base0A-hex}'><b>{}</b></span>";
                  weeks = "<span color='#${base0C-hex}'><b>W{:%V}</b></span>";
                };
                mode = "year";
                mode-mon-col = 3;
                on-click-right = "mode";
                on-scroll = 1;
                weeks-pos = "right";
              };
              format = "󰥔 {:%H:%M}";
              format-alt = "󰥔 {:%A, %B %d, %Y (%R)} ";
              tooltip-format = ''<span size='9pt' font='Fira Code'>{calendar}</span>'';
            };

            cpu = {
              format = "󰍛 {usage}%";
              format-alt = "{icon0}{icon1}{icon2}{icon3}";
              format-icons = [
                "▁"
                "▂"
                "▃"
                "▄"
                "▅"
                "▆"
                "▇"
                "█"
              ];
              interval = 10;
            };

            "battery" = {
              format = "{icon} {capacity}";
              #interval = 60;
              format-icons = [
                "󰂎" "󰂎" "󰁾" "󰁾" "󰁾" "󰁹" "󰁹"
              ];
              states = {
                  warning  = 30;
                  critical = 15;
              };
            };

            "custom/gpu-usage" = {
              exec = "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits";
              format = "{}";
              interval = 10;
            };

            "custom/logo" = {
              exec = "echo ' '";
              format = "{}";
            };

            "custom/submap" = {
              exec = "${submapScript}/bin/submap-status";
              format = "{}";
            };

            "hyprland/window" = {
              format = "  {}";
              rewrite = {
                "(.*) — Mozilla Firefox" = "$1 󰈹";
                "(.*)Steam" = "Steam 󰓓";
              };
              separate-outputs = true;
            };

            "hyprland/language" = {
              format = " {}";
              format-en = "english";
            };

            memory = {
              format = "󰾆 {percentage}%";
              format-alt = "󰾅 {used}GB";
              interval = 30;
              max-length = 10;
              tooltip = true;
              tooltip-format = " {used:0.1f}GB/{total:0.1f}GB";
            };

            network = {
              format-disconnected = " Disconnected";
              format-ethernet = "󱘖 Wired";
              format-linked = "󱘖 {ifname} (No IP)";
              format-wifi = "󰤨 {essid}";
              interval = 5;
              max-length = 30;
              tooltip-format = "󱘖 {ipaddr}  {bandwidthUpBytes}  {bandwidthDownBytes}";
            };

            pulseaudio = {
              format = "{icon}  {volume}%";
              format-icons = {
                car = " ";
                default = [
                  ""
                  ""
                  ""
                ];
                hands-free = " ";
                headphone = " ";
                headset = " ";
                phone = " ";
                portable = " ";
              };
              format-muted = " {volume}%";
              on-click = "${pavucontrol} -t 3";
              on-click-middle = "${pamixer} -t";
              on-scroll-down = "${pamixer} -d 5";
              on-scroll-up = "${pamixer} -i 5";
              scroll-step = 5;
              tooltip-format = "{icon} {desc} {volume}%";
            };

            "pulseaudio#microphone" = {
              format = "{format_source}";
              format-source = "  {volume}%";
              format-source-muted = "  {volume}%";
              on-click = "${pavucontrol} -t 4";
              on-click-middle = "${pamixer} --default-source -t";
              on-scroll-down = "${pamixer} --default-source -d 5";
              on-scroll-up = "${pamixer} --default-source -i 5";
              scroll-step = 5;
            };

            tray = {
              icon-size = 15;
              spacing = 5;
            };

            idle_inhibitor = {
              format = "{icon}";
              format-icons = {
                activated = "";
                deactivated = "";
              };
            };
          };
        };

        style = ''
          /* colors: https://github.com/nix-community/stylix/blob/master/modules/gtk/gtk.css.mustache */

          * {
              border: none;
              border-radius: 0px;
              font-family: "JetBrainsMono Nerd Font";
              font-weight: bold;
              font-size: 14px;
              min-height: 0px;
          }

          window#waybar {
          }

          tooltip {
              background: @theme_unfocused_base_color;
              color: @theme_text_color;
              /* border-radius: 10px; */
              border-width: 1px;
              border-style: solid;
              border-color: @accent_bg_color;
          }

          #workspaces button {
              box-shadow: none;
              text-shadow: none;
              padding: 0px;
              border-radius: 7px;
              padding-right: 0px;
              padding-left: 4px;
              margin-right: 7px;
              margin-left: 7px;
              color: @theme_text_color;
              animation: gradient_f 2s ease-in infinite;
              transition: all 0.2s cubic-bezier(.55,-0.68,.48,1.682);
          }

          #workspaces button.active {
              color: @accent_color;
              animation: gradient_f 20s ease-in infinite;
              transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
          }

          #workspaces button:hover {
              color: @accent_color;
              animation: gradient_f 20s ease-in infinite;
              transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
          }

          #cpu,
          #memory,
          #custom-power,
          #clock,
          #workspaces,
          #window,
          #custom-updates,
          #network,
          #bluetooth,
          #pulseaudio,
          #custom-wallchange,
          #custom-mode,
          #custom-submap,
          #idle_inhibitor,
          #battery
          #tray {
              color: @theme_text_color;
              background: shade(alpha(@theme_text_colors, 0.9), 1.25);
              opacity: 1;
              padding: 0px;
              margin: 3px 3px 3px 3px;
          }

          #battery {
              color: @green_1
          }

          /* resource monitor block */

          #cpu {
              border-radius: 10px 0px 0px 10px;
              margin-left: 25px;
              padding-left: 12px;
              padding-right: 4px;
          }

          #memory {
              border-radius: 0px 10px 10px 0px;
              border-left-width: 0px;
              padding-left: 4px;
              padding-right: 12px;
              margin-right: 6px;
          }


          /* date time block */
          #clock {
              color: @yellow_1;
              padding-left: 4px;
              padding-right: 4px;
          }


          /* workspace window block */
          #workspaces {
              border-radius: 9px 9px 9px 9px;
              background: mix(@theme_unfocused_base_color,white,0.1);
          }

          #window {
              /* border-radius: 0px 10px 10px 0px; */
              /* padding-right: 12px; */
          }

          window#waybar.battery-warning {
              border-width: 4px 0 4px 0;
              border-style: solid;
              border-color: @yellow_1;
          }

          window#waybar.battery-critical {
              border-width: 4px 0 4px 0;
              border-style: solid;
              border-color: @red_1;
          }

          /* control center block */
          #custom-updates {
              border-radius: 10px 0px 0px 10px;
              margin-left: 6px;
              padding-left: 12px;
              padding-right: 4px;
          }

          #network {
              color: @purple_1;
              padding-left: 4px;
              padding-right: 4px;
          }

          #language {
              color: @orange_1;
              padding-left: 9px;
              padding-right: 9px;
          }

          #cpu {
              color: @orange_1;
              padding-left: 4px;
              padding-right: 4px;
          }

          #memory {
              color: @blue_1;
              padding-left: 4px;
              padding-right: 4px;
          }

          #bluetooth {
              color: @blue_1;
              padding-left: 4px;
              padding-right: 0px;
          }

          #pulseaudio {
              color: @red_1;
              padding-left: 4px;
              padding-right: 0px;
          }

          #pulseaudio.microphone {
              color: @red_1;
              padding-left: 0px;
              padding-right: 4px;
          }

          #idle_inhibitor {
              color: @blue_1;
              padding-left: 8px;
              padding-right: 8px;
          }

          /* system tray block */
          #custom-mode {
              border-radius: 10px 0px 0px 10px;
              margin-left: 6px;
              padding-left: 12px;
              padding-right: 4px;
          }

          #custom-logo {
              margin-left: 6px;
              padding-right: 4px;
              color: @blue_1;
              font-size: 16px;

          }

          #tray {
              padding-left: 4px;
              padding-right: 4px;
          }
        '';

        systemd.enable = true;
        # todo
        # systemd.target = lib.mkIf config.modules.home.waybar.enable "sway-session.target";
      };
    };
}
