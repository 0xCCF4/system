{ stylix, lib, config, mine, pkgs, ... }@inputs: with lib; {
  imports = [
    stylix.nixosModules.stylix
  ];

  options.mine.wallpapers = with types;
    {
      primaryColor = mkOption {
        type = str;
        default = config.lib.stylix.colors.base0B;
        description = "Primary color for the wallpaper.";
      };

      secondaryColor = mkOption {
        type = str;
        default = config.lib.stylix.colors.base07;
        description = "Secondary color for the wallpaper.";
      };

      snowflake = {
        sourceImage = mkOption {
          type = path;
          default = ../../lib/binaryWallpapers/snowflake.png;
          description = "Path to the snowflake image.";
        };
        sourceData = mkOption {
          type = path;
          default = ../../lib/binaryWallpapers/Nix_Snowflake_Logo.svg;
          description = "Path to the snowflake data.";
        };
        wallpaper = mkOption {
          type = path;
          description = "Path to the snowflake wallpaper.";
        };
      };
    };

  config = {
    stylix.enable = mkDefault true;
    stylix.base16Scheme = mkDefault "${pkgs.base16-schemes}/share/themes/gruvbox-dark-hard.yaml";

    mine.wallpapers = {
      snowflake.wallpaper =
        let
          cfg = config.mine.wallpapers;
        in
        ((pkgs.callPackage mine.lib.mkBinaryWallpaper { }) {
          name = "snowflake-binary-image";
          src_image = cfg.snowflake.sourceImage;
          src_data = cfg.snowflake.sourceData;
          primaryColor = cfg.primaryColor;
          secondaryColor = cfg.secondaryColor;
          description = "A binary snowflake.";
        }).output;
    };

    stylix.image = mkDefault config.mine.wallpapers.snowflake.wallpaper;
  };
}
