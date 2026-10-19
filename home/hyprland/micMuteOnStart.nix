{ pkgs
, lib
, config
, ...
}:
with lib;
let
  pactl = getExe' pkgs.pulseaudio "pactl";

  muteAllMicsScript = pkgs.writeShellScriptBin "mute-all-mics" ''
    set -euo pipefail
    while IFS=$'\t' read -r idx name _; do
      case "$name" in
        *.monitor) continue ;;
      esac
      ${pactl} set-source-mute "$name" 1
    done < <(${pactl} list short sources)
  '';
in
{
  config = mkIf config.wayland.windowManager.hyprland.enable {
    systemd.user.services.mute-mics-on-start = {
      Unit = {
        Description = "Mute all microphones at Hyprland session start";
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = getExe muteAllMicsScript;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
  };
}
