{ config
, lib
, osConfig
, self
, inputs
, ...
}:
with lib; with builtins;
{
  imports = [
    ./traits.nix
    inputs.impermanence.homeManagerModules.impermanence
  ];

  options.home.mine = with types;
    {
      persistence.enable = mkOption {
        type = bool;
        default = self.lib.evalMissingOption osConfig "mine.persistence.enable" false;
        description = "Enable home persistence";
      };

      persistence.defaultHomeFolders = mkOption {
        type = bool;
        default = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
        description = "Add default persistence folders/files: Documents, Pictures, Music, Videos, Desktop, keyrings";
      };

      persistence.defaultFolders = mkOption {
        type = bool;
        default = true;
        description = "Add default persistence folders/files: .ssh, .gnupg";
      };

      persistence.defaultRust = mkOption {
        type = bool;
        default = config.home.mine.traits.hasDevelopment;
        description = "Add default persistence folders/files: .cargo, .rustup";
      };

      persistence.data.directories = mkOption {
        default = [ ];
        description = "Persistent directories. These files are included within backups.";
      };
      persistence.data.files = mkOption {
        default = [ ];
        description = "Persistent file. These files are included within backups.";
      };

      persistence.cache.directories = mkOption {
        default = [ ];
        description = "Persistent cache directory. These files are not included in backups.";
      };
      persistence.cache.files = mkOption {
        default = [ ];
        description = "Persistent cache file. These files are not included in backups.";
      };
    };

  config =
    let
      cfg = config.home.mine.persistence;
    in
    mkIf cfg.enable {
      assertions = [
        {
          assertion = (hasAttr "persistence" (osConfig.mine or { })) != null;
          message = with noxa.lib.ansi; "${bold+fgYellow}NixOS ${fgCyan}mine.${italic}persistence${fgYellow+noItalic} module option not found! Did you not import the ${fgCyan}mine.persistence${fgYellow} module?";
        }
      ];

      home.mine.persistence.data.directories = mkMerge [
        (mkIf cfg.defaultFolders [
          ".ssh"
          ".gnupg"
        ])
        (mkIf cfg.defaultHomeFolders [
          "Desktop"
          "Downloads"
          "Music"
          "Pictures"
          "Documents"
          "Videos"
          ".local/share/keyrings"
        ])
      ];
      home.mine.persistence.cache.directories = mkIf cfg.defaultRust [
        ".cargo"
        ".rustup"
      ];

      home.persistence."${osConfig.mine.persistence.dataDirectory}/home/${config.home.username}" = {
        removePrefixDirectory = false;
        files = cfg.data.files;
        directories = cfg.data.directories;
        allowOther = true;
      };

      home.persistence."${osConfig.mine.persistence.cacheDirectory}/home/${config.home.username}" = {
        removePrefixDirectory = false;
        files = cfg.cache.files;
        directories = cfg.cache.directories;
        allowOther = true;
      };
    };
}
