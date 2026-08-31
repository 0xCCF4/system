{ config
, lib
, ...
}:
with lib;
{
  imports = [
    ./traits.nix
  ];

  options.home.mine = with types; {
    devenv.enable = mkOption {
      type = bool;
      default = config.home.mine.traits.hasDevelopment;
      description = "Enable devenv auto-activation for project shells (native fish hook)";
    };
  };

  config = mkIf config.home.mine.devenv.enable {
    programs.fish.interactiveShellInit = ''
      devenv hook fish | source
    '';
  };
}
