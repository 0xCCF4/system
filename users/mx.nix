{ config, noxa, mine, ... }: {
  imports = mine.lib.optionalsIfExist [
    ../external/private/users/mx.nix
  ];

  config = {
    users.users.mx =
      {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        createHome = true;
        homeMode = "700";
        uid = 1000;
        passwordFileOverride = config.age.secrets.${noxa.lib.secrets.computeIdentifier {
          ident = "mx-user-password";
          module = "mine.users";
        }}.path;
      };

    noxa.secrets.def = [
      {
        ident = "mx-user-password";
        module = "mine.users";
        generator.script = "alnum";
      }
    ];

    mine.homeManager.users.include = [ "mx" ];
  };
}
