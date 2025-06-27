{ home-manager
, lib
, config
, impermanence
, noxa
, stylix
, mine
, ...
}: with lib; with builtins; {
  imports = [
    home-manager.nixosModules.default
  ];

  options.mine.homeManager = with types; {
    users.all = mkOption {
      type = bool;
      default = true;
      description = "Add home manager config for each configured system user.";
    };
    users.include = mkOption {
      type = listOf str;
      default = [ ];
      description = "Additionally include the following users";
    };
    users.exclude = mkOption {
      type = listOf str;
      default = [ ];
      description = "Exclude the given users from auto config.";
    };
    config.path = mkOption {
      type = path;
      default = ../../users;
      description = "Path where home configuration is stored";
    };
    config.pattern = mkOption {
      type = str;
      default = "USER:home.nix";
      description = "File name template for the home configurations. 'USER' is replaced with the username.";
    };
  };

  config =
    let
      cfg = config.mine.homeManager;

      usersAll = attrsets.mapAttrsToList (name: val: name) (attrsets.filterAttrs (name: data: data.enable && data.isNormalUser) config.users.users);
      usersInclusive = usersAll ++ cfg.users.include;
      usersExclude = filter (user: !(elem user cfg.users.exclude)) usersInclusive;
      users = unique usersExclude;

      resolveImport = name: cfg.config.path + "/${(replaceStrings [ "USER" ] [ name ] cfg.config.pattern)}";

      imports = listToAttrs (map
        (user: {
          name = user;
          value = resolveImport user;
        })
        users);
    in
    {
      assertions = attrsets.mapAttrsToList
        (user: path: {
          assertion = pathExists path;
          message = with noxa.lib.ansi; "${fgYellow}The home manager main configuration for user ${fgCyan}'${user}'${fgYellow} does not exist at location ${fgCyan}'${toString path}'${fgYellow}. Did you add it to git?${reset}";
        })
        imports;

      home-manager = {
        backupFileExtension = "hmbackup";

        extraSpecialArgs = {
          inherit impermanence;
          inherit noxa;
          inherit stylix;
          inherit home-manager;
          inherit mine;
        };

        users = attrsets.mapAttrs
          (user: path: { ... }: {
            imports = [
              path
              ../home
            ];

            config = {
              home.username = user;
              home.stateVersion = mkDefault config.system.stateVersion;
            };

          })
          imports;
      };
    };
}
