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
    ./unfree.nix
  ];

  options.mine.homeManager = with types; {
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

      users = unique (filter (user: !(elem user cfg.users.exclude)) cfg.users.include);

      resolveImport = name: cfg.config.path + "/${(replaceStrings [ "USER" ] [ name ] cfg.config.pattern)}";

      imports = listToAttrs (map
        (user: {
          name = user;
          value = resolveImport user;
        })
        users);
    in
    {
      assertions = mkMerge (map
        (name: [{
          assertion = hasAttr name config.users.users;
          message = with noxa.lib.ansi; "${fgYellow}The user ${fgCyan}'${name}'${fgYellow} does not exist, but included in home-manager configuration.${reset}";
        }
          {
            assertion = config.users.users.${name}.isNormalUser;
            message = with noxa.lib.ansi; "${fgYellow}The user ${fgCyan}'${name}'${fgYellow} is not a normal user, but included in home-manager configuration.${reset}";
          }
          {
            assertion = config.users.users.${name}.enable;
            message = with noxa.lib.ansi; "${fgYellow}The user ${fgCyan}'${name}'${fgYellow} is not enabled, but included in home-manager configuration.${reset}";
          }
          {
            assertion = pathExists imports.${name};
            message = with noxa.lib.ansi; "${fgYellow}The home manager main configuration for user ${fgCyan}'${name}'${fgYellow} does not exist at location ${fgCyan}'${toString imports.${name}}'${fgYellow}. Did you add it to git?${reset}";
          }
          {
            assertion = config.home-manager.useGlobalPkgs -> ((config.home-manager.users.${name}.home.mine.unfree.allowAll or false) -> config.mine.unfree.allowAll);
            message = with noxa.lib.ansi; "${fgYellow}You are using global packages for home-manager, but the user ${fgCyan}'${name}'${fgYellow} declared to use unfree packages without restrictions. Since you manage packages in your nixos config, you must set the global option ${fgCyan}'mine.unfree.allowAll = true'${fgYellow} to allow unrestricted unfree packages as requested by the user config.${reset}";
          }])
        users);

      home-manager = {
        backupFileExtension = "hmbackup";
        useUserPackages = true;
        useGlobalPkgs = true;

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

      mine.unfree.allowList = mkMerge (map (user: config.home-manager.users.${user}.home.mine.unfree.allowList) users);
    };
}
