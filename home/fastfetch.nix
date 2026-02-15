{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
{
  options.home.mine.fastfetch.startup = with types; mkOption {
    type = bool;
    default = self.lib.evalMissingOption osConfig "mine.presets.isServer" false;
    description = "Run fastfetch on shell startup";
  };

  config = mkIf config.home.mine.fastfetch.startup {
    home.packages = [ pkgs.fastfetch ];
    programs.zsh.initContent = lib.mkAfter ''
      ${getExe pkgs.fastfetch}
    '';

    programs.fish.shellInitLast = lib.mkAfter ''
      ${getExe pkgs.fastfetch}
    '';
  };
}
