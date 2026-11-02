{ pkgs
, lib
, config
, ...
}:
with lib;
let
  pactl = getExe' pkgs.pulseaudio "pactl";
  jq = getExe pkgs.jq;

  muteMicsScript = pkgs.writeShellScriptBin "mute-mics" ''
    set -euo pipefail
    declare -A seen=()

    scan() {
      local -A now=()
      local name port avail mute key
      while IFS=$'\x1f' read -r name port avail mute; do
        key="$port|$avail"
        now[$name]=$key
        [[ "$mute" == true ]] && continue  # never re-mute a muted source: no event feedback loop
        if [[ "$avail" == "not available" || ! -v seen[$name] || "''${seen[$name]}" != "$key" ]]; then
          ${pactl} set-source-mute "$name" 1 || true
        fi
      done < <(${pactl} -f json list sources | ${jq} -r '
        .[]
        | select((.name | endswith(".monitor")) | not)
        | select(.properties."device.class" != "monitor")
        | (.active_port // "") as $p
        | ([(.ports // [])[] | select(.name == $p) | .availability] | first // "") as $a
        | [.name, $p, $a, (.mute | tostring)] | join("\u001f")')
      seen=()
      for name in "''${!now[@]}"; do seen[$name]=''${now[$name]}; done
    }

    scan
    while read -r line; do
      case "$line" in
        *" on source #"* | *" on card #"*) scan ;;
      esac
    done < <(${pactl} subscribe)
  '';
in
{
  config = mkIf config.wayland.windowManager.hyprland.enable {
    systemd.user.services.mute-mics-on-start = {
      Unit = {
        Description = "Mute microphones at session start and on port switch / hotplug";
        PartOf = [ "hyprland-session.target" ];
        After = [ "pipewire-pulse.service" "wireplumber.service" ];
      };
      Service = {
        ExecStart = getExe muteMicsScript;
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
