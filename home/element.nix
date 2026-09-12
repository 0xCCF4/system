{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  imports = [
    ./persistence.nix
  ];

  options.home.mine.element = with types; {
    enable = mkOption {
      type = bool;
      default = self.lib.evalMissingOption osConfig.mine.presets "isWorkstation" false;
      description = "Enable Element (Matrix client) desktop app";
    };

    settings = mkOption {
      default =
        let
          luxDomain = self.nixosConfigurations.lux.config.mine.info.domain;
        in
        {
          disable_custom_urls = true;
          disable_guests = true;
        }
        // optionalAttrs (luxDomain != null) {
          default_server_config."m.homeserver" = {
            base_url = "https://${self.nixosConfigurations.lux.config.mine.services.matrix.domains.homeserver}";
            server_name = luxDomain;
          };
        };
      description = "Settings passed through to programs.element-desktop.settings, i.e. Element's config.json";
    };
  };

  config =
    let
      cfg = config.home.mine.element;
    in
    mkIf cfg.enable {
      programs.element-desktop = {
        enable = true;
        settings = cfg.settings;
      };

      home.mine.persistence.data.directories = [
        ".config/Element"
      ];

      wayland.windowManager.hyprland.settings.permission = [
        {
          binary = "${getExe config.programs.element-desktop.package}";
          type = "screencopy";
          mode = "allow";
        }
      ];
    };
}
