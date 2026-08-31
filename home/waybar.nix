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
  pactl = "${getExe' pkgs.pulseaudio "pactl"}";
  setsid = "${getExe' pkgs.util-linux "setsid"}";
  hyprctl = "${
    if config.wayland.windowManager.hyprland.package != null then
      config.wayland.windowManager.hyprland.package
    else
      osConfig.programs.hyprland.package
  }/bin/hyprctl";

  luxIp = self.nixosConfigurations.lux.config.mine.info.public.ipv4;
in
{
  options.home.mine.waybar = with lib.types; {
    zfsDataset = mkOption {
      type = str;
      default = "pool";
      description = "The ZFS dataset whose free space is shown by the disk-usage waybar module.";
    };

    weatherTempCold = mkOption {
      type = int;
      default = 17;
      description = "Weather tooltip: temperatures at or below this (°C) are colored blue (cold).";
    };

    weatherTempHot = mkOption {
      type = int;
      default = 25;
      description = "Weather tooltip: temperatures at or below this (°C) are colored green (comfortable); above it, red (hot).";
    };

    weatherRainThreshold = mkOption {
      type = int;
      default = 50;
      description = "Weather tooltip: rain chance (%) above this is highlighted blue.";
    };

    weatherSunThreshold = mkOption {
      type = int;
      default = 75;
      description = "Weather tooltip: sunshine chance (%) above this is highlighted yellow.";
    };

    diskFreeWarningGB = mkOption {
      type = int;
      default = 50;
      description = "Disk tile: free space (GB) at or below this turns the tile yellow (warning).";
    };

    diskFreeCriticalGB = mkOption {
      type = int;
      default = 10;
      description = "Disk tile: free space (GB) at or below this turns the tile red (critical).";
    };

    batteryNeutral = mkOption {
      type = int;
      default = 80;
      description = "Battery tile: capacity (%) at or below this switches from green to neutral gray.";
    };

    batteryWarning = mkOption {
      type = int;
      default = 30;
      description = "Battery tile: capacity (%) at or below this turns the tile yellow (warning).";
    };

    batteryCritical = mkOption {
      type = int;
      default = 15;
      description = "Battery tile: capacity (%) at or below this turns the tile red (critical).";
    };

    memWarning = mkOption {
      type = int;
      default = 85;
      description = "Memory tile: usage (%) at or above this turns the tile yellow (warning).";
    };

    memCritical = mkOption {
      type = int;
      default = 95;
      description = "Memory tile: usage (%) at or above this turns the tile red (critical).";
    };

    todoLists = mkOption {
      type = listOf str;
      default = [ config.home.mine.todoman.defaultList ];
      description = ''
        Which todoman lists the todo tile, and its on-click view, show.
        Defaults to the configured todoman default list. Set to an
        empty list to show every list. Set to a custom list of names to
        show a specific subset.
      '';
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
        ${getExe config.programs.todoman.package} --porcelain list ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.todoLists} | ${getExe pkgs.jq} -c '
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
          | ($upcomingItems | map(select((.due | localtime | strftime("%Y-%m-%d")) == (now | localtime | strftime("%Y-%m-%d")))) | length) as $dueToday
          | {
              text: (
                if ($due | length) == 0 then
                  ""
                else
                  "TODO \($due | length)"
                end
              ),
              class: (
                if $overdue > 0 then ["critical"]
                elif $dueToday > 0 then ["warning"]
                else [] end
              ),
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

      weatherRefreshSignal = 8;

      citySetterScript = pkgs.writeShellScriptBin "waybar-set-city" ''
        set -euo pipefail
        stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/waybar"
        mkdir -p "$stateDir"
        if [ $# -lt 1 ]; then
          rm -f "$stateDir/city"
          echo "Weather city override removed, falling back to ${defaultCity}"
        else
          printf '%s' "$*" > "$stateDir/city"
          echo "Weather city set to: $*"
        fi
        ${getExe' pkgs.procps "pkill"} -RTMIN+${toString weatherRefreshSignal} waybar 2>/dev/null || true
      '';

      weatherReformatScript = pkgs.writeText "weather-reformat.py" ''
        import sys, re

        def temp_color(temp_val):
            if temp_val <= ${toString cfg.weatherTempCold}:
                return "${config.lib.stylix.colors.base0D-hex}"
            elif temp_val <= ${toString cfg.weatherTempHot}:
                return "${config.lib.stylix.colors.base0B-hex}"
            else:
                return "${config.lib.stylix.colors.base08-hex}"

        def colored_temp(temp_str, width=0):
            return f'<span foreground="#{temp_color(int(temp_str))}">{temp_str:>{width}}°</span>'

        def colored_humidity(hum_str, width=0):
            return f'<span foreground="#${config.lib.stylix.colors.base0C-hex}">{hum_str:>{width}}%</span>'

        text = sys.stdin.read()

        # strip wind entirely (top summary line + per-hour breakdown entries)
        text = re.sub(r"Wind: [^\n]*\n", "", text)
        text = re.sub(r", Wind \d+%", "", text)

        # color and align the current-condition block: description/temp, Feels
        # Like, Humidity and Location all share one label column and, where
        # they're temperatures, one value column too.
        def colored_header(m):
            desc, temp, feels, humidity, location = m.groups()
            feels_label = "Feels Like:"
            humidity_label = "Humidity:"
            location_label = "Location:"
            label_width = max(len(desc), len(feels_label), len(humidity_label), len(location_label))
            temp_width = max(len(temp), len(feels))
            return (
                f"<b>{desc:<{label_width}}</b> {colored_temp(temp, width=temp_width)}\n"
                f"{feels_label:<{label_width}} {colored_temp(feels, width=temp_width)}\n"
                f"{humidity_label:<{label_width}} {colored_humidity(humidity, width=temp_width)}\n"
                f"{location_label:<{label_width}} {location}"
            )

        text = re.sub(
            r"^<b>([^<]*)</b> (\d+)°\nFeels Like: (\d+)°\nHumidity: (\d+)%\nLocation: ([^\n]*)",
            colored_header,
            text,
            count=1,
            flags=re.MULTILINE,
        )

        lines = text.split("\n")
        out = []
        i = 0
        day_header_re = re.compile(r"^<b>.*</b>$")
        hour_re = re.compile(r"^(\d{2}) (\S+)\s+(\d+)° (.*)$")
        daily_temp_re = re.compile(r"(\S+)(\s+)(\d+)°")

        def colored_daily_temp(m):
            icon, sep, val = m.groups()
            color = temp_color(int(val))
            return f'<span foreground="#{color}">{icon}</span>{sep}<span foreground="#{color}">{val}°</span>'

        while i < len(lines):
            line = lines[i]
            if day_header_re.match(line) and i + 1 < len(lines) and lines[i + 1].strip() and not hour_re.match(lines[i + 1]):
                # merge the day header with its summary line so columns line up below,
                # coloring the daily high/low icon+temperature pairs on the way
                summary = daily_temp_re.sub(colored_daily_temp, lines[i + 1])
                out.append(line + "  " + summary)
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
                if rain and int(rain) > ${toString cfg.weatherRainThreshold}:
                    rain_str = f'<span foreground="#${config.lib.stylix.colors.base0D-hex}">{rain_str}</span>'
                if sunshine and int(sunshine) > ${toString cfg.weatherSunThreshold}:
                    sunshine_str = f'<span foreground="#${config.lib.stylix.colors.base0A-hex}">{sunshine_str}</span>'
                desc = desc if desc else ""

                temp_span = colored_temp(temp, width=3)

                rain_icon_span = '<span foreground="#${config.lib.stylix.colors.base0D-hex}"></span>'
                cloud_icon_span = '<span foreground="#${config.lib.stylix.colors.base03-hex}"></span>'
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
                gsub("Location: (?<v>[^\n]*)"; "Location: <span foreground=\"#${config.lib.stylix.colors.base0B-hex}\">\(.v)</span>")
                | gsub("<b>(?<t>[^<]*)</b>"; "<span foreground=\"#${config.lib.stylix.colors.base0D-hex}\"><b>\(.t)</b></span>")
              )
            '
      '';

      diskScript = pkgs.writeShellScriptBin "disk-status" ''
        set -euo pipefail

        # tile: only the configured dataset drives text/color
        freeGB="$(${getExe' pkgs.zfs "zfs"} list --json -p -o available "${cfg.zfsDataset}" \
          | ${getExe pkgs.jq} --arg name "${cfg.zfsDataset}" -r \
              '(.datasets[$name].properties.available.value | tonumber) / 1073741824 | round')"

        if [ "$freeGB" -lt ${toString cfg.diskFreeCriticalGB} ]; then
          class='["critical"]'
        elif [ "$freeGB" -lt ${toString cfg.diskFreeWarningGB} ]; then
          class='["warning"]'
        else
          class='[]'
        fi

        # tooltip: every pool on the system, auto-discovered
        rows=("POOL\tSIZE\tALLOC\tFREE\tCAP\tHEALTH")
        while IFS=$'\t' read -r name size alloc free cap health; do
          rows+=("$name\t$size\t$alloc\t$free\t$cap\t$health")
        done < <(${getExe' pkgs.zfs "zpool"} list -H -o name,size,alloc,free,capacity,health)

        tooltip="$(printf '%b\n' "''${rows[@]}" \
            | ${getExe' pkgs.util-linux "column"} -t -s $'\t' \
            | awk 'NR==1 { print "<b>" $0 "</b>"; next } { print "<span weight=\"normal\">" $0 "</span>" }')"

        ${getExe pkgs.jq} -n -c --arg text "DISK ''${freeGB}" --arg tooltip "$tooltip" --argjson class "$class" \
          '{text: $text, class: $class, tooltip: $tooltip}'
      '';

      networkScript = pkgs.writeShellScriptBin "network-status" ''
        set -euo pipefail

        checkTcp() {
          timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
        }

        # bind by source IP rather than interface name - SO_BINDTODEVICE
        # (what --interface <name> uses) needs CAP_NET_RAW, but bind() to a
        # plain local address doesn't, so this works unprivileged.
        checkInternetVia() {
          timeout 3 ${getExe pkgs.curl} -k --interface "$1" --connect-timeout 2 -s -o /dev/null "https://9.9.9.9" 2>/dev/null
        }

        ipv4Of() {
          ${getExe' pkgs.iproute2 "ip"} -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
        }

        wifiSsid() {
          ${getExe' pkgs.iw "iw"} dev "$1" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p'
        }

        defaultIface="$(${getExe' pkgs.iproute2 "ip"} route show default 2>/dev/null | awk '{print $5; exit}')"

        if [ -z "$defaultIface" ]; then
          text="NET --"
          class='["critical"]'
          tooltip="No default route"
        else
          text="NET $defaultIface"

          if ! checkTcp 9.9.9.9 443; then
            class='["critical"]'
            defaultStatus="no internet connection"
          ${lib.optionalString (luxIp != null) ''
          elif ! checkTcp ${luxIp} 443; then
            class='["warning"]'
            defaultStatus="no connection to lux (${luxIp})"
          ''}
          else
            class='[]'
            defaultStatus="connected"
          fi

          rows=("IFACE\tSSID\tADDRESS\tSTATUS")
          while read -r dev; do
            [ "$dev" = "lo" ] && continue

            addr="$(ipv4Of "$dev")"
            [ -z "$addr" ] && addr="-"

            if [ -d "/sys/class/net/$dev/wireless" ]; then
              ssid="$(wifiSsid "$dev")"
              ssid="''${ssid:-not associated}"
            else
              ssid="-"
            fi

            if [ "$dev" = "$defaultIface" ]; then
              status="$defaultStatus"
            elif [ "$addr" = "-" ]; then
              status="no IPv4 address"
            elif checkInternetVia "$addr"; then
              status="connected"
            else
              status="no internet"
            fi

            rows+=("$dev\t$ssid\t$addr\t$status")
          done < <(${getExe' pkgs.iproute2 "ip"} -o link show up | awk -F': ' '{print $2}')

          tooltip="$(printf '%b\n' "''${rows[@]}" \
            | ${getExe' pkgs.util-linux "column"} -t -s $'\t' \
            | awk 'NR==1 { print "<b>" $0 "</b>"; next } { print "<span weight=\"normal\">" $0 "</span>" }')"
        fi

        ${getExe pkgs.jq} -n -c --arg text "$text" --arg tooltip "$tooltip" --argjson class "$class" \
          '{text: $text, class: $class, tooltip: $tooltip}'
      '';

      cpuScript = pkgs.writeShellScriptBin "cpu-status" ''
        set -euo pipefail

        emit() {
          mapfile -t before < <(grep '^cpu' /proc/stat)
          sleep 0.3
          mapfile -t after < <(grep '^cpu' /proc/stat)

          rows=("CORE\tUSAGE")
          avgUsage=0
          for i in "''${!before[@]}"; do
            read -r label u1 n1 s1 i1 io1 irq1 sirq1 st1 _ <<< "''${before[$i]}"
            read -r _     u2 n2 s2 i2 io2 irq2 sirq2 st2 _ <<< "''${after[$i]}"

            total1=$((u1 + n1 + s1 + i1 + io1 + irq1 + sirq1 + st1))
            total2=$((u2 + n2 + s2 + i2 + io2 + irq2 + sirq2 + st2))
            idle1=$((i1 + io1))
            idle2=$((i2 + io2))
            totald=$((total2 - total1))
            idled=$((idle2 - idle1))

            usage=0
            [ "$totald" -gt 0 ] && usage=$(( (100 * (totald - idled)) / totald ))

            name="$label"
            if [ "$label" = "cpu" ]; then
              name="avg"
              avgUsage="$usage"
            fi
            rows+=("$name\t''${usage}%")
          done

          tooltip="$(printf '%b\n' "''${rows[@]}" \
            | ${getExe' pkgs.util-linux "column"} -t -s $'\t' -R 2 \
            | awk 'NR==1 { print "<b>" $0 "</b>"; next } { print "<span weight=\"normal\">" $0 "</span>" }')"

          ${getExe pkgs.jq} -n -c --arg text "CPU ''${avgUsage}" --arg tooltip "$tooltip" \
            '{text: $text, tooltip: $tooltip}'
        }

        while true; do
          emit
          sleep 0.7
        done
      '';

      memScript = pkgs.writeShellScriptBin "mem-status" ''
        set -euo pipefail

        emit() {
          totalKb="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
          availKb="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
          usedKb=$((totalKb - availKb))
          percentage=$((usedKb * 100 / totalKb))
          totalGb="$(awk -v kb="$totalKb" 'BEGIN { printf "%.1f", kb / 1048576 }')"
          usedGb="$(awk -v kb="$usedKb" 'BEGIN { printf "%.1f", kb / 1048576 }')"

          if [ "$percentage" -ge ${toString cfg.memCritical} ]; then
            class='["critical"]'
          elif [ "$percentage" -ge ${toString cfg.memWarning} ]; then
            class='["warning"]'
          else
            class='[]'
          fi

          tooltip=" ''${usedGb}GB/''${totalGb}GB"

          ${getExe pkgs.jq} -n -c --arg text "MEM ''${percentage}" --arg tooltip "$tooltip" --argjson class "$class" \
            '{text: $text, class: $class, tooltip: $tooltip}'
        }

        while true; do
          emit
          sleep 1
        done
      '';

      volumeScript = pkgs.writeShellScriptBin "volume-status" ''
        set -euo pipefail

        sinkVol() {
          ${pactl} get-sink-volume "$1" | grep -oP '\d+(?=%)' | head -1
        }
        sinkMuted() {
          ${pactl} get-sink-mute "$1" | awk '{print $2}'
        }
        truncate() {
          local s="$1" max="$2"
          if [ "''${#s}" -gt "$max" ]; then
            printf '%s' "''${s:0:$((max - 1))}."
          else
            printf '%s' "$s"
          fi
        }

        emit() {
          defaultSink="$(${pactl} get-default-sink)"
          vol="$(sinkVol "$defaultSink")"
          muted="$(sinkMuted "$defaultSink")"

          if [ "$muted" = "yes" ]; then
            text="VOL MUTE"
          else
            text="VOL ''${vol}%"
          fi

          if [ "$muted" != "yes" ] && [ "''${vol:-0}" -gt 100 ]; then
            class='[]'
          else
            class='["normal"]'
          fi

          rows=("SINK\tVOLUME\tMUTED")
          activeLine=0
          i=0
          while IFS=$'\t' read -r idx name _; do
            i=$((i + 1))
            v="$(sinkVol "$name")"
            m="$(sinkMuted "$name")"
            if [ "$name" = "$defaultSink" ]; then
              activeLine=$((i + 1))
            fi
            rows+=("$(truncate "$name" 30)\t''${v}%\t$m")
          done < <(${pactl} list short sinks)

          tooltip="$(printf '%b\n' "''${rows[@]}" \
            | ${getExe' pkgs.util-linux "column"} -t -s $'\t' \
            | awk -v active="$activeLine" '
                NR==1      { print "<b>" $0 "</b>"; next }
                NR==active { print "<span weight=\"normal\"><u>" $0 "</u></span>"; next }
                { print "<span weight=\"normal\">" $0 "</span>" }
              ')"

          ${getExe pkgs.jq} -n -c --arg text "$text" --arg tooltip "$tooltip" --argjson class "$class" \
            '{text: $text, class: $class, tooltip: $tooltip}'
        }

        emit
        ${pactl} subscribe 2>/dev/null | while read -r line; do
          case "$line" in
            *"on sink"*|*"on server"*) emit ;;
          esac
        done
      '';

      micScript = pkgs.writeShellScriptBin "mic-status" ''
        set -euo pipefail

        sourceVol() {
          ${pactl} get-source-volume "$1" | grep -oP '\d+(?=%)' | head -1
        }
        sourceMuted() {
          ${pactl} get-source-mute "$1" | awk '{print $2}'
        }
        truncate() {
          local s="$1" max="$2"
          if [ "''${#s}" -gt "$max" ]; then
            printf '%s' "''${s:0:$((max - 1))}."
          else
            printf '%s' "$s"
          fi
        }

        emit() {
          defaultSource="$(${pactl} get-default-source)"

          rows=("SOURCE\tVOLUME\tMUTED")
          activeLine=0
          i=0
          anyUnmuted=0
          while IFS=$'\t' read -r idx name _; do
            case "$name" in
              *.monitor) continue ;;
            esac
            i=$((i + 1))
            v="$(sourceVol "$name")"
            m="$(sourceMuted "$name")"
            [ "$m" = "no" ] && anyUnmuted=1
            if [ "$name" = "$defaultSource" ]; then
              activeLine=$((i + 1))
            fi
            rows+=("$(truncate "$name" 30)\t''${v}%\t$m")
          done < <(${pactl} list short sources)

          if [ "$anyUnmuted" -eq 1 ]; then
            text=""
            class='[]'
          else
            text=""
            class='["source-muted"]'
          fi

          tooltip="$(printf '%b\n' "''${rows[@]}" \
            | ${getExe' pkgs.util-linux "column"} -t -s $'\t' \
            | awk -v active="$activeLine" '
                NR==1      { print "<b>" $0 "</b>"; next }
                NR==active { print "<span weight=\"normal\"><u>" $0 "</u></span>"; next }
                { print "<span weight=\"normal\">" $0 "</span>" }
              ')"

          ${getExe pkgs.jq} -n -c --arg text "$text" --arg tooltip "$tooltip" --argjson class "$class" \
            '{text: $text, class: $class, tooltip: $tooltip}'
        }

        emit
        ${pactl} subscribe 2>/dev/null | while read -r line; do
          case "$line" in
            *"on source"*|*"on server"*) emit ;;
          esac
        done
      '';
    in
    {
      home.packages = [ pkgs.playerctl pkgs.wttrbar citySetterScript weatherScript diskScript networkScript cpuScript memScript volumeScript micScript ];

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
              "custom/cpu"
              "custom/mem"
              "custom/disk"
              "custom/network"
              "bluetooth"
              "battery"
              "custom/todo"
              "custom/volume"
              "custom/microphone"
              "idle_inhibitor"
              "tray"
              "clock"
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

            "custom/cpu" = {
              exec = "${getExe cpuScript}";
              return-type = "json";
              format = "{}";
              restart-interval = 10; # 10 sec
              tooltip = true;
            };

            "custom/mem" = {
              exec = "${getExe memScript}";
              return-type = "json";
              format = "{}";
              restart-interval = 10; # 10 sec
              tooltip = true;
            };

            "battery" = {
              format = "BAT {capacity}";
              #interval = 60; # 1 min
              states = {
                neutral = cfg.batteryNeutral;
                warning = cfg.batteryWarning;
                critical = cfg.batteryCritical;
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
              signal = weatherRefreshSignal;
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
              on-click = "${setsid} -f ${getExe config.programs.kitty.package} --hold -e ${getExe config.programs.todoman.package} list ${lib.concatMapStringsSep " " lib.escapeShellArg cfg.todoLists} &";
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

            "custom/network" = {
              exec = "${getExe networkScript}";
              return-type = "json";
              format = "{}";
              interval = 5; # 5 sec
              tooltip = true;
            };

            "custom/volume" = {
              exec = "${getExe volumeScript}";
              return-type = "json";
              format = "{}";
              restart-interval = 5; # 5 sec
              tooltip = true;
              on-click = "${setsid} -f ${pavucontrol} -t 3 &";
              on-click-middle = "${pamixer} -t";
              on-scroll-down = "${pamixer} -d 5";
              on-scroll-up = "${pamixer} -i 5";
              scroll-step = 5;
            };

            "custom/microphone" = {
              exec = "${getExe micScript}";
              return-type = "json";
              format = "{}";
              restart-interval = 5; # 5 sec
              tooltip = true;
              on-click = "${setsid} -f ${pavucontrol} -t 4 &";
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

          #workspaces button.urgent {
              background: @red_1;
              color: #${base00-hex};
          }

          /* resource-stat cluster: neutral gray chips, plain-text labels.
             Color only signals something worth noticing - see the
             module-specific override rules below. */
          #custom-cpu,
          #custom-mem,
          #custom-disk,
          #custom-network,
          #bluetooth,
          #custom-volume,
          #custom-microphone,
          #battery,
          #clock,
          #custom-todo,
          #workspaces button {
              border-radius: 6px;
              padding: 2px 10px;
              margin: 3px 2px;
          }

          #custom-cpu     { background: #${base01-hex}; color: @theme_text_color; }
          #custom-mem     { background: #${base01-hex}; color: @theme_text_color; }
          #custom-mem.warning  { background: @yellow_1; color: #${base00-hex}; }
          #custom-mem.critical { background: @red_1;    color: #${base00-hex}; }
          #custom-disk    { background: #${base01-hex}; color: @theme_text_color; }
          #custom-network { background: #${base01-hex}; color: @theme_text_color; }
          #bluetooth      { background: #${base01-hex}; color: @theme_text_color; }
          #custom-todo    { background: #${base01-hex}; color: @theme_text_color; }
          #clock          { background: @blue_1;   color: #${base00-hex}; }

          /* disk free space: default gray, warn as it fills up */
          #custom-disk.warning  { background: @yellow_1; color: #${base00-hex}; }
          #custom-disk.critical { background: @red_1;    color: #${base00-hex}; }

          /* network: default gray, yellow if lux is unreachable, red if
             there's no internet connection at all (takes priority) */
          #custom-network.warning  { background: @yellow_1; color: #${base00-hex}; }
          #custom-network.critical { background: @red_1;    color: #${base00-hex}; }

          /* volume: default gray, cyan once boosted past 100% */
          #custom-volume { background: #${base01-hex}; color: @theme_text_color; }
          #custom-volume:not(.normal) { background: #${base0C-hex}; color: #${base00-hex}; }

          /* microphone: default gray, red while live (privacy-sensitive) */
          #custom-microphone { background: #${base01-hex}; color: @theme_text_color; }
          #custom-microphone:not(.source-muted) { background: @red_1; color: #${base00-hex}; }

          /* the muted-mic glyph () sits off-center in its own advance
             width and renders shifted right - shrinking the left padding
             (which is what actually pushes glyph content rightward in a
             shrink-to-fit box) pulls it back in line with the other icons */
          #custom-microphone.source-muted {
              padding: 2px 12px 2px 7px;
          }

          /* battery: green above 80%, gray in the middle range, yellow/red as it drains */
          #battery         { background: @green_1;  color: #${base00-hex}; }
          #battery.neutral  { background: #${base01-hex}; color: @theme_text_color; }
          #battery.warning  { background: @yellow_1; color: #${base00-hex}; }
          #battery.critical { background: @red_1;    color: #${base00-hex}; }

          /* todo: default gray, yellow if something's due today, red if overdue */
          #custom-todo.warning  { background: @yellow_1; color: #${base00-hex}; }
          #custom-todo.critical { background: @red_1;    color: #${base00-hex}; }

          /* nudged 1px right to compensate for the toggle glyph's off-center bearing */
          #idle_inhibitor {
              background: #${base01-hex};
              color: @theme_text_color;
              border-radius: 6px;
              padding: 2px 11px 2px 8px;
              margin: 3px 2px;
          }

          /* idle inhibitor: default gray, blue while inhibiting */
          #idle_inhibitor.activated {
              background: @blue_1;
              color: #${base00-hex};
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
