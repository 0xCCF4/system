{ inputs
, config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  imports = [
    ./persistence.nix
  ];

  config = {
    home.mine.persistence.cache.directories = mkIf (config.programs.fish.enable) [
      ".local/share/fish"
    ];

    programs.fish = {
      enable = mkDefault true;

      functions = {
        __sync_tmux_ssh_env = {
          onEvent = "fish_prompt";
          body = ''
            if set -q TMUX
              set -l val (tmux show-environment SSH_CONNECTION 2>/dev/null | string replace -r '^SSH_CONNECTION=' "")
              if test -n "$val"
                set -gx SSH_CONNECTION $val
              else
                set -e SSH_CONNECTION
              end
            end
          '';
        };
      };
    };
  };
}
