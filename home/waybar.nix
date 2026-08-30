{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
# Originally from https://github.com/vimjoyer/nixconf Licensed under the MIT License.
# Chip-based restyle inspired by:
#   - https://github.com/HANCORE-linux/waybar-themes/tree/main/config/V2.a (chip/pill structure, workspace numeral technique)
#   - https://github.com/HANCORE-linux/waybar-themes/tree/main/config/V2.1-3 (plain-text resource-stat labels)
with lib;
let
  cfg = config.home.mine.waybar;

  pamixer = "${getExe pkgs.pamixer}";
  pavucontrol = "${getExe pkgs.pavucontrol}";
  hyprctl = "${
    if config.wayland.windowManager.hyprland.package != null then
      config.wayland.windowManager.hyprland.package
    else
      osConfig.programs.hyprland.package
  }/bin/hyprctl";
in
{
  options.home.mine.waybar = with lib.types; {
    zfsDataset = mkOption {
      type = str;
      default = "pool";
      description = "The ZFS dataset whose free space is shown by the disk-usage waybar module.";
    };
  };

  config =
    let
      submapScript = pkgs.writeShellScriptBin "submap-status" ''
        filterDefault() {
          if [ "$1" = "default" ]; then
            echo ""
          else
            echo "$1"
          fi
        }

        handle() {
          case $1 in
            submap*) filterDefault "''${1#*>>}" ;;
          esac
        }

        filterDefault "$(${hyprctl} submap | tr -d '\n\r')"

        ${pkgs.socat}/bin/socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read -r line; do handle "$line"; done
      '';

      workspaces = {
        format = "{icon}";
        format-icons = {
          "1" = "I";
          "2" = "II";
          "3" = "III";
          "4" = "IV";
          "5" = "V";
          "6" = "VI";
          "7" = "VII";
          "8" = "VIII";
          "9" = "IX";
          "10" = "X";
          urgent = "";
          special = "";
          default = "{name}";
        };
        on-click = "activate";
        # persistent_workspaces = { "*" = 10; };
      };

      tomatScript = pkgs.writeShellScriptBin "tomat-status" ''
        ${getExe config.services.tomat.package} watch -f "{state} {phase} {time}"
      '';

      todoScript = pkgs.writeShellScriptBin "todo-status" ''
        ${getExe config.programs.todoman.package} --porcelain list | ${getExe pkgs.jq} -c '
          def priority_marker:
            if .priority == 0 then
              ""
            elif .priority <= 4 then
              "<span foreground=\"#${config.lib.stylix.colors.base08-hex}\"></span> "
            elif .priority == 5 then
              "<span foreground=\"#${config.lib.stylix.colors.base0D-hex}\"></span> "
            else
              "<span foreground=\"#${config.lib.stylix.colors.base0B-hex}\"></span> "
            end;
          def fmt_line:
            "\(.due | localtime | strftime("%a %H:%M"))  \(priority_marker)\(.summary)";
          def fmt_line_overdue:
            "<span foreground=\"#${config.lib.stylix.colors.base08-hex}\">\(.due | localtime | strftime("%a %H:%M"))</span>  \(priority_marker)\(.summary)";
          def plain_line:
            "\(.due | localtime | strftime("%a %H:%M"))  \(if .priority == 0 then "" else "X " end)\(.summary)";
          [.[] | select(.due != null and (.start == null or .start <= now))]
          | sort_by([.due, (if .priority == 0 then 999 else .priority end)]) as $due
          | ($due | map(select(.due < now)) | sort_by([(if .priority == 0 then 999 else .priority end), .due])) as $overdueItems
          | ($due | map(select(.due >= now))) as $upcomingItems
          | ($due | map(plain_line | length) | (if length > 0 then max else 0 end)) as $maxlen
          | ($overdueItems | length) as $overdue
          | {
              text: (
                if ($due | length) == 0 then
                  ""
                else
                  "TODO \($due | length)"
                end
              ),
              class: (if $overdue > 0 then ["overdue"] else [] end),
              tooltip: (
                if ($due | length) == 0 then
                  "Nothing due"
                else
                  (
                    ($overdueItems | map(fmt_line_overdue))
                    + (if ($overdueItems | length) > 0 and ($upcomingItems | length) > 0 then [("─" * $maxlen)] else [] end)
                    + ($upcomingItems | map(fmt_line))
                  ) | join("\n")
                end
              )
            }
        '
      '';

      defaultCity = self.lib.evalMissingOption osConfig "mine.info.weatherCity" "Berlin";

      citySetterScript = pkgs.writeShellScriptBin "waybar-set-city" ''
        set -euo pipefail
        if [ $# -lt 1 ]; then
          echo "Usage: waybar-set-city <city name>" >&2
          exit 1
        fi
        stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/waybar"
        mkdir -p "$stateDir"
        printf '%s' "$*" > "$stateDir/city"
        echo "Weather city set to: $*"
      '';

      weatherReformatScript = pkgs.writeText "weather-reformat.py" ''
        import sys, re

        text = sys.stdin.read()

        # strip wind entirely (top summary line + per-hour breakdown entries)
        text = re.sub(r"Wind: [^\n]*\n", "", text)
        text = re.sub(r", Wind \d+%", "", text)

        lines = text.split("\n")
        out = []
        i = 0
        day_header_re = re.compile(r"^<b>.*</b>$")
        hour_re = re.compile(r"^(\d{2}) (\S+)\s+(\d+)° (.*)$")

        while i < len(lines):
            line = lines[i]
            if day_header_re.match(line) and i + 1 < len(lines) and lines[i + 1].strip() and not hour_re.match(lines[i + 1]):
                # merge the day header with its summary line so columns line up below
                out.append(line + "  " + lines[i + 1])
                i += 2
                continue
            m = hour_re.match(line)
            if m:
                hh, icon, temp, rest = m.groups()
                parts = [p.strip() for p in rest.split(",") if p.strip()]
                cond_pct = {}
                desc = None
                for p in parts:
                    pm = re.match(r"^(.*?)\s+(\d+)%$", p)
                    if pm:
                        name, pct = pm.groups()
                        cond_pct[name.strip()] = pct
                        if desc is None:
                            desc = name.strip()
                    elif desc is None:
                        desc = p
                rain = cond_pct.get("Rain", "")
                overcast = cond_pct.get("Overcast", "")
                sunshine = cond_pct.get("Sunshine", "")
                rain_str = f"{rain:>3}%" if rain else "    "
                overcast_str = f"{overcast:>3}%" if overcast else "    "
                sunshine_str = f"{(sunshine if sunshine else '0'):>3}%"
                desc = desc if desc else ""

                temp_val = int(temp)
                if temp_val <= 17:
                    temp_color = "${config.lib.stylix.colors.base0D-hex}"
                elif temp_val <= 25:
                    temp_color = "${config.lib.stylix.colors.base0B-hex}"
                else:
                    temp_color = "${config.lib.stylix.colors.base08-hex}"
                temp_span = f'<span foreground="#{temp_color}">{temp:>3}°</span>'

                rain_icon_span = '<span foreground="#${config.lib.stylix.colors.base0D-hex}"></span>'
                cloud_icon_span = '<span foreground="#${config.lib.stylix.colors.base04-hex}"></span>'
                sun_icon_span = '<span foreground="#${config.lib.stylix.colors.base0A-hex}"></span>'

                out.append(f"{hh} {icon} {temp_span}  {rain_icon_span} {rain_str}  {cloud_icon_span} {overcast_str}  {sun_icon_span} {sunshine_str}  {desc}")
                i += 1
                continue
            out.append(line)
            i += 1

        sys.stdout.write("\n".join(out))
      '';

      weatherScript = pkgs.writeShellScriptBin "weather-status" ''
        set -euo pipefail
        stateFile="''${XDG_STATE_HOME:-$HOME/.local/state}/waybar/city"
        city="$(cat "$stateFile" 2>/dev/null || true)"
        city="''${city:-${defaultCity}}"
        raw="$(${getExe pkgs.wttrbar} --nerd --location "$city")"
        tooltip="$(printf '%s' "$raw" | ${getExe pkgs.jq} -r '.tooltip' | ${getExe' pkgs.python3 "python3"} ${weatherReformatScript})"
        printf '%s' "$raw" | ${getExe pkgs.jq} -c --arg tooltip "$tooltip" '
            .tooltip = $tooltip
            | .tooltip |= (
                gsub("Feels Like: (?<v>[^\n]*)"; "Feels Like: <span foreground=\"#${config.lib.stylix.colors.base09-hex}\">\(.v)</span>")
                | gsub("Humidity: (?<v>[^\n]*)"; "Humidity: <span foreground=\"#${config.lib.stylix.colors.base0C-hex}\">\(.v)</span>")
                | gsub("Location: (?<v>[^\n]*)"; "Location: <span foreground=\"#${config.lib.stylix.colors.base0B-hex}\">\(.v)</span>")
                | gsub("<b>(?<t>[^<]*)</b>"; "<span foreground=\"#${config.lib.stylix.colors.base0D-hex}\"><b>\(.t)</b></span>")
              )
            '
      '';

      diskScript = pkgs.writeShellScriptBin "disk-status" ''
        set -euo pipefail
        ${getExe' pkgs.zfs "zfs"} list --json -p -o available "${cfg.zfsDataset}" \
          | ${getExe pkgs.jq} --arg name "${cfg.zfsDataset}" -c '
              (.datasets[$name].properties.available.value | tonumber) as $freeBytes
              | ($freeBytes / 1073741824 * 10 | round / 10) as $freeGB
              | { text: "DISK \($freeGB)GB", tooltip: "ZFS dataset \($name): \($freeGB)GB free" }
            '
      '';
    in
    {
      home.packages = [ pkgs.playerctl pkgs.wttrbar citySetterScript weatherScript diskScript ];

      programs.waybar = with config.lib.stylix.colors; {
        enable = mkDefault (
          (self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false)
          && (osConfig.programs.hyprland.enable || config.wayland.windowManager.hyprland.enable)
        );

        settings = {
          mainBar = {
            mod = "dock";
            layer = "top";
            gtk-layer-shell = true;
            height = 14;
            position = "top";

            modules-left = [
              "custom/logo"
              "custom/weather"
              "hyprland/workspaces"
              "custom/submap"
            ];
            modules-center = [
              "mpris"
            ];
            modules-right = [
              "custom/tomat"
              "cpu"
              "memory"
              "custom/disk"
              "network"
              "bluetooth"
              "pulseaudio"
              "pulseaudio#microphone"
              "idle_inhibitor"
              "battery"
              "custom/todo"
              "clock"
              "tray"
            ];

            "wlr/workspaces" = workspaces;
            "hyprland/workspaces" = workspaces;

            bluetooth = {
              format = "";
              format-connected = "BT {num_connections}";
              format-disabled = "";
              tooltip-format = " {device_alias}";
              tooltip-format-connected = "{device_enumerate}";
            };

            mpris = {
              format = "{player_icon} {dynamic}  <span foreground=\"#${base03-hex}\" size=\"small\">{position}/{length}</span>";
              format-paused = "{status_icon} {dynamic}  <span foreground=\"#${base03-hex}\" size=\"small\">{position}/{length}</span>";
              # exclude position/length from the default dynamic-order so they
              # aren't shown twice - we render them ourselves above in `format`
              dynamic-order = [ "title" "artist" "album" ];
              player-icons = {
                "default" = "󰐊";
                "mpv" = "󰝚";
                "ncspot" = "󰝚";
              };
              status-icons = {
                "paused" = "󰏤";
              };
              interval = 1; # 1 sec
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
              format = "{:%H:%M}";
              format-alt = "{:%A, %B %d, %Y (%R)}";
              tooltip-format = "<span size='9pt' font='Fira Code'>{calendar}</span>";
            };

            cpu = {
              format = "CPU {usage}%";
              interval = 10; # 10 sec
            };

            "battery" = {
              format = "BAT {capacity}%";
              #interval = 60; # 1 min
              states = {
                warning = 30;
                critical = 15;
              };
            };

            "custom/gpu-usage" = {
              exec = "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits";
              format = "{}";
              interval = 10; # 10 sec
            };

            "custom/weather" = {
              exec = "${getExe weatherScript}";
              format = "{}°";
              tooltip = true;
              return-type = "json";
              interval = 1800; # 30 min
            };

            "custom/disk" = {
              exec = "${getExe diskScript}";
              return-type = "json";
              format = "{}";
              interval = 300; # 5 min
              tooltip = true;
            };

            "custom/logo" = {
              exec = "echo ' '";
              format = "{}";
            };

            "custom/submap" = {
              exec = "${getExe submapScript}";
              format = "{}";
            };

            "custom/tomat" = mkIf (config.services.tomat.enable) {
              exec = "${getExe config.services.tomat.package} watch -f \"{phase} {time}\"";
              return-type = "json";
              format = "{text}";
              tooltip = true;
            };

            "custom/todo" = mkIf (config.programs.todoman.enable) {
              exec = "${getExe todoScript}";
              return-type = "json";
              format = "{}";
              hide-empty-text = true;
              interval = 60; # 1 min
              tooltip = true;
              on-click = "${getExe config.programs.kitty.package} --hold -e ${getExe config.programs.todoman.package} list";
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
              format = "MEM {percentage}%";
              interval = 30; # 30 sec
              tooltip = true;
              tooltip-format = " {used:0.1f}GB/{total:0.1f}GB";
            };

            network = {
              format = "NET";
              format-wifi = "NET {ifname}";
              format-ethernet = "NET {ifname}";
              format-disconnected = "NET --";
              interval = 5; # 5 sec
              tooltip-format = "{ipaddr}  {bandwidthUpBytes}  {bandwidthDownBytes}";
            };

            pulseaudio = {
              format = "VOL {volume}%";
              format-muted = "VOL MUTE";
              on-click = "${pavucontrol} -t 3";
              on-click-middle = "${pamixer} -t";
              on-scroll-down = "${pamixer} -d 5";
              on-scroll-up = "${pamixer} -i 5";
              scroll-step = 5;
              tooltip-format = "{desc} {volume}%";
            };

            "pulseaudio#microphone" = {
              format = "{format_source}";
              format-source = "";
              format-source-muted = "";
              tooltip-format = "{volume}%";
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
          /* Chip-based restyle inspired by:
             - https://github.com/HANCORE-linux/waybar-themes/tree/main/config/V2.a (chip/pill structure, workspace numeral technique)
             - https://github.com/HANCORE-linux/waybar-themes/tree/main/config/V2.1-3 (plain-text resource-stat labels) */

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
              border-width: 1px;
              border-style: solid;
              border-color: @accent_bg_color;
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

          /* workspace chips */
          #workspaces button,
          #workspaces button:hover,
          #workspaces button:focus,
          #workspaces button:backdrop,
          #workspaces button.active {
              
          }

          #workspaces button {
              background: #${base01-hex};
              color: @theme_text_color;
              
          }

          #workspaces button label {
              padding: 0;
              margin: 0;
          }

          #workspaces button.active {
              background: @accent_color;
              color: #${base00-hex};
          }

          #workspaces button:hover {
              background: @red_1;
              color: #${base00-hex};
          }

          /* resource-stat cluster: solid accent chips, plain-text labels */
          #cpu,
          #memory,
          #custom-disk,
          #network,
          #bluetooth,
          #pulseaudio,
          #battery,
          #clock,
          #custom-todo,
          #workspaces button {
              border-radius: 6px;
              padding: 2px 10px;
              margin: 3px 2px;
          }

          #cpu            { background: @orange_1; color: #${base00-hex}; }
          #memory         { background: @blue_1;   color: #${base00-hex}; }
          #custom-disk    { background: #${base0C-hex}; color: #${base00-hex}; }
          #network        { background: @purple_1; color: #${base00-hex}; }
          #bluetooth      { background: @blue_1;   color: #${base00-hex}; }
          #pulseaudio, #pulseaudio.microphone { background: @red_1; color: #${base00-hex}; }
          #battery        { background: @green_1;  color: #${base00-hex}; }
          #clock          { background: @blue_1;   color: #${base00-hex}; }
          #custom-todo    { background: @yellow_1; color: #000000; }

          /* inset shadow instead of a real border - never changes the tile's box size */
          #custom-todo.overdue {
              box-shadow: inset 0 0 0 4px @red_1;
          }

          /* nudged 1px right to compensate for the toggle glyph's off-center bearing */
          #idle_inhibitor {
              background: @purple_1;
              color: #${base00-hex};
              border-radius: 6px;
              padding: 2px 11px 2px 8px;
              margin: 3px 2px;
          }

          /* NixOS logo: Stylix accent, larger glyph */
          #custom-logo {
              background: @accent_color;
              color: #${base00-hex};
              border-radius: 6px;
              padding: 2px 12px;
              margin: 3px 2px;
              font-size: 16px;
          }

          /* utility modules: neutral dark chips, icon content unchanged */
          #tray,
          #custom-weather,
          #custom-submap,
          #custom-tomat,
          #mpris {
              background: #${base01-hex};
              color: @theme_text_color;
              border-radius: 6px;
              padding: 2px 10px;
              margin: 3px 2px;
          }
        '';

        systemd.enable = true;
        systemd.targets = [ "hyprland-session.target" ];
      };
    };
}
