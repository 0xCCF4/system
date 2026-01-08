{ config
, pkgs
, lib
, mine
, osConfig
, ...
}:
with lib;
{
  options.home.mine.fastfetch.startup = with types; mkOption {
    type = bool;
    default = mine.lib.evalMissingOption osConfig "mine.presets.isServer" false;
    description = "Run fastfetch on shell startup";
  };

  config = mkIf config.home.mine.fastfetch.startup {
    home.packages = [ pkgs.fastfetch ];
    programs.zsh.initContent = lib.mkAfter ''
      ${pkgs.fastfetch}/bin/fastfetch
    '';

    programs.fish.shellInitLast = lib.mkAfter ''
      ${pkgs.fastfetch}/bin/fastfetch
    '';
  };
}
