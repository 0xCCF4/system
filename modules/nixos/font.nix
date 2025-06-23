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
    let
      presets = config.mine.presets;
    in
    mkOption {
      type = bool;
      default = presets.isWorkstation;
      description = "Add some standard fonts to the system.";
    };

  config =
    mkIf config.mine.defaultFonts {
      fonts = {
        packages = with pkgs; [
          jetbrains-mono
          newcomputermodern
          roboto
          openmoji-color
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          mplus-outline-fonts.githubRelease
          dina-font
          proggyfonts
          wqy_zenhei
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
