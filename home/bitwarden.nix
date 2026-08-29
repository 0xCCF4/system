{ config
, lib
, pkgs
, osConfig
, self
, ...
}:
with lib;
let
  cfg = config.home.mine.bitwarden;
  isWorkstation = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
  serverUrl = "https://${self.nixosConfigurations.lux.config.mine.services.caddyProxy.routes.vaultwarden.public.domain}";

  # Formats `rbw list --fields name,user` into aligned rows: a display column
  # (padded name + user, for the selector to show/search) followed by the raw
  # name and user as hidden fields, so the caller can recover them exactly
  # regardless of padding.
  rbwListFormatAwk = pkgs.writeShellScript "rbw-list-format" ''
    awk -F'\t' '
      { name[NR] = $1; user[NR] = $2; if (length($1) > w) w = length($1) }
      END {
        for (i = 1; i <= NR; i++) {
          printf "%-*s  %s\t%s\t%s\n", w, name[i], user[i], name[i], user[i]
        }
      }
    '
  '';

  # Copies the password for `$1` (optional username `$2`) to the clipboard,
  # then clears it again after 30s -- but only if the clipboard still holds
  # exactly what we put there, so we don't clobber something copied since.
  rbwCopyClear = pkgs.writeShellScript "rbw-copy-clear" ''
    set -euo pipefail

    name="$1"
    user="''${2:-}"

    if [ -n "$user" ]; then
      password="$(rbw get "$name" "$user")"
    else
      password="$(rbw get "$name")"
    fi

    printf '%s' "$password" | wl-copy

    (
      sleep 30
      if [ "$(wl-paste -n 2>/dev/null)" = "$password" ]; then
        wl-copy --clear
      fi
    ) >/dev/null 2>&1 &
    disown
  '';

  rbwFzf = pkgs.writeShellApplication {
    name = "rbw-fzf";
    runtimeInputs = [ pkgs.rbw pkgs.fzf pkgs.gawk pkgs.wl-clipboard ];
    text = ''
      selection="$(rbw list --fields name,user | ${rbwListFormatAwk} | fzf --delimiter='\t' --with-nth=1 --prompt='rbw> ')"
      if [ -z "$selection" ]; then
        exit 0
      fi

      IFS=$'\t' read -r _ name user <<< "$selection"

      ${rbwCopyClear} "$name" "$user"
    '';
  };

  rbwRofi = pkgs.writeShellApplication {
    name = "rbw-rofi";
    runtimeInputs = [ pkgs.rbw pkgs.gawk pkgs.wl-clipboard config.programs.rofi.package ];
    text = ''
      selection="$(rbw list --fields name,user | ${rbwListFormatAwk} | rofi -dmenu -p 'rbw> ' -display-columns 1 -display-column-separator '\t')"
      if [ -z "$selection" ]; then
        exit 0
      fi

      IFS=$'\t' read -r _ name user <<< "$selection"

      ${rbwCopyClear} "$name" "$user"
    '';
  };

in
{
  options.home.mine.bitwarden = {
    enable = mkOption {
      type = types.bool;
      default = isWorkstation;
      description = ''
        Install rbw, the official bw CLI, and the official Bitwarden
        desktop app, pointed at the self-hosted Vaultwarden server.
      '';
    };

    email = mkOption {
      type = types.str;
      description = ''
        The email address to log in to the Vaultwarden server with.

        rbw's config file is managed declaratively (a read-only symlink into
        the Nix store), so this cannot be set imperatively via
        `rbw config set email`.
      '';
    };

    rofiPickerPackage = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = rbwRofi;
      description = ''
        The rbw-rofi wrapper package, exposed so other modules (e.g.
        keybindings) can reference its executable.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.rbw.enable = true;

    xdg.configFile."rbw/config.json".text = builtins.toJSON {
      email = cfg.email;
      base_url = serverUrl;
      pinentry = getExe pkgs.pinentry-rofi;
    };

    home.packages = [
      pkgs.bitwarden-cli
      pkgs.bitwarden-desktop
      rbwFzf
      rbwRofi
    ];

    home.activation.bwConfigServer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${getExe pkgs.bitwarden-cli} config server ${serverUrl}
    '';
  };
}
