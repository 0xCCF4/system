{ config
, lib
, ...
}:
with lib; with builtins;
{
  config = {
    programs.tmux = {
      enable = mkDefault true;

      clock24 = mkDefault true;

      extraConfig = readFile ./tmux.conf;
    };
  };
}
