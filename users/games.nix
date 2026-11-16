{ ... }: {
  description = "Games";
  authorizedKeys = [ ];
  hashedPassword = null;
  home =
    { lib
    , config
    , nixosConfig
    , pkgs
    , ...
    }:
      with pkgs;
      with lib;
      {
        home.mine.traits.traits = [
          "gaming"
        ];

        home.mine.rss.enable = false;
      };
  os = { ... }: {
    mine.steam = true;
  };
}
