{ pkgs
, lib
, config
, ...
}:
with lib;
{
  imports = [
    ./presets.nix
  ];

  options.mine.defaultFonts = with types;
    mkOption {
      type = bool;
      default = config.mine.presets.isWorkstation;
      description = "Add some standard fonts to the system.";
    };

  config =
    mkIf config.mine.defaultFonts {
      fonts = {
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          mplus-outline-fonts.githubRelease
          dina-font
          proggyfonts

          jetbrains-mono
          #newcomputermodern
          #roboto
          openmoji-color
          #wqy_zenhei
          nerd-fonts.fira-code
          #google-fonts
          #(nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
        ];

        fontconfig = {
          hinting.autohint = true;
          defaultFonts = {
            emoji = [ "OpenMoji Color" ];
          };
        };
      };
    };
}
