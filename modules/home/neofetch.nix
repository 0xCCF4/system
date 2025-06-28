{ config
, pkgs
, lib
, mine
, osConfig
, ...
}:
with lib;
{
  options.home.mine.neofetch.startup = with types; mkOption {
    type = bool;
    default = mine.lib.evalMissingOption osConfig "mine.presets.isServer" false;
    description = "Run neofetch on shell startup";
  };

  config = mkIf config.home.mine.neofetch.startup {
    home.packages = [ pkgs.neofetch ];

    programs.zsh.initContent = lib.mkAfter ''
      ${pkgs.neofetch}/bin/neofetch
    '';

    programs.fish.shellInitLast = lib.mkAfter ''
      ${pkgs.neofetch}/bin/neofetch
    '';
  };
}
