{ config, noxa, mine, lib, options, ... }: with lib; {
  imports = mine.lib.optionalsIfExist [
    ../external/private/users/games.nix
  ];

  config = {
    users.users.games =
      {
        isNormalUser = true;
        createHome = true;
        homeMode = "700";
        uid = 1001;
        passwordFileOverride = mkIf (!config.age.rekey.initialRollout) (
          config.age.secrets.${noxa.lib.secrets.computeIdentifier {
            ident = "games-user-password";
            module = "mine.users";
          }}.path
        );
      };

    noxa.secrets.def = mkIf config.noxa.secrets.enable [
      {
        ident = "games-user-password";
        module = "mine.users";
        generator.script = "alnum";
      }
    ];

    mine.homeManager.users.include = [ "games" ];

    home-manager.users.games = {
      config = {
        home.mine.traits.traits = [
          "gaming"
        ];
      };
    };

    mine.steam = true;
  };
}
