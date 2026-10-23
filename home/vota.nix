{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  options.home.mine.vota = with types; {
    enable = mkOption {
      type = bool;
      default = self.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false;
      description = "Install the `vota ballot …` client for Vota's admin API.";
    };

    package = mkOption {
      type = pkgs.lib.types.package;
      default = pkgs.vota;
      description = "The Vota package to use.";
    };

    url = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        Default server URL, used when neither `--url` nor VOTA_URL is given.
      '';
      example = "https://vote.example.org/";
    };

    tokenFile = mkOption {
      type = nullOr str;
      default = null;
      description = ''
        File holding the default Admin Token (e.g. an agenix secret), used
        when neither `--token`/`--token-file` nor VOTA_ADMIN_TOKEN is given.
      '';
      example = "/run/agenix/vota-admin-token";
    };
  };

  config =
    let
      cfg = config.home.mine.vota;

      # Only fills in the environment variables when they are unset; the
      # client itself prefers --url/--token/--token-file over them.
      wrapped = pkgs.symlinkJoin {
        name = "vota-wrapped";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/vota \
            ${optionalString (cfg.url != null) "--set-default VOTA_URL ${escapeShellArg cfg.url}"} \
            ${optionalString (cfg.tokenFile != null) ''--run ${escapeShellArg ''
              if [ -z "''${VOTA_ADMIN_TOKEN:-}" ] && [ -r ${escapeShellArg cfg.tokenFile} ]; then
                VOTA_ADMIN_TOKEN="$(< ${escapeShellArg cfg.tokenFile})"
                export VOTA_ADMIN_TOKEN
              fi
            ''}''}
        '';
      };
    in
    mkIf cfg.enable {
      home.packages = [
        (if cfg.url == null && cfg.tokenFile == null then cfg.package else wrapped)
      ];
    };
}
