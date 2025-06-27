{ lib, nixosConfig, ... }: with lib; with builtins; {
  options.home.mine.autostart = with types; mkOption {
    type = listOf package;
    default = [ ];
    description = "Packages to autostart on graphical login.";
  };

  imports = [
    ./gnome.nix
  ];
}
