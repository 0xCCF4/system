{ inputs
, config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  options.home.mine = with types;
    {
      versionControl.userEmail = mkOption {
        type = str;
        description = "The email address to use for commits";
      };
      versionControl.userName = mkOption {
        type = str;
        description = "The name to use for commits";
      };
    };

  config =
    let
      cfg = config.home.mine.versionControl;
    in
    {
      programs.git = {
        enable = mkDefault true;
        # delta.options = todo
        ignores = [
          "*~"
          "*.swp"
          "*.jj"
        ];
        lfs.enable = true;
        # signing = true; todo
        # signing.key = todo
        # signing.signbydefault = true; todo

        settings = {
          init.defaultBranch = "main";
          user.email = cfg.userEmail;
          user.name = cfg.userName;
        };
      };

      programs.jujutsu = {
        enable = mkDefault true;
        settings = {
          user.email = cfg.userEmail;
          user.name = cfg.userName;
        };
      };

      programs.delta = {
        enable = mkDefault true;
        enableGitIntegration = mkDefault true;
      };
    };
}
