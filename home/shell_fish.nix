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

  options.mine.sshFishFallback = mkOption {
    type = types.bool;
    default = true;
    description = "Whether interactive `ssh` sessions with no explicit remote command should spawn `fish` on the remote if available, falling back to the account's default shell otherwise.";
  };

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

        ssh = mkIf config.mine.sshFishFallback {
          wraps = "ssh";
          body = ''
            set -l hostargs (string match -rv '^-' -- $argv)
            if isatty stdin; and test (count $hostargs) -eq 1
              command ssh -t $argv 'if command -v fish >/dev/null 2>&1; then exec fish -l; else exec "$SHELL" -l; fi'
            else
              command ssh $argv
            end
          '';
        };
      };
    };
  };
}
