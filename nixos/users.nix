{ config, lib, users, pkgs, self, ... }@inputs: with lib; with builtins;
{
  options.mine = with types; {
    users = mkOption {
      type = listOf str;
      default = [ ];
      description = "List of users to be created on the system.";
    };
    fakeUsers = mkOption {
      type = listOf str;
      default = [ ];
      description = "List of users to create home-manager configurations for but are system users created elsewhere.";
    };
    admins = mkOption {
      type = listOf str;
      default = [ ];
      description = "List of users to be given admin (wheel) privileges.";
    };
  };

  imports = mapAttrsToList
    (username: data: {
      config = mkIf (elem username config.mine.users) ((data.os or ({ ... }: { })) inputs);
    })
    users;

  config =
    let
      fakeUsers = unique (filter (user: !(elem user config.mine.users)) config.mine.fakeUsers);
      uniqUsers = unique config.mine.users;
      usersNotInConfig = filter (user: !(hasAttr user users)) uniqUsers;
    in
    {
      assertions = [
        {
          assertion = length usersNotInConfig == 0;
          message = "The user '${head usersNotInConfig}' is listed as a user on the system but is not defined in the 'users' module.";
        }
      ];

      # all admins are also users
      mine.users = config.mine.admins;

      users.users = mkMerge (map
        (userName:
          let
            userModule = users.${userName};
          in
          {
            "${userName}" = {
              isNormalUser = true;
              uid = userModule.uid;
              extraGroups = (optional (elem userName config.mine.admins) "wheel");
              hashedPassword = mkIf (userModule ? "hashedPassword") userModule.hashedPassword;
              openssh.authorizedKeys.keys = userModule.authorizedKeys;
              shell = mkIf (userModule ? "shell") (mkOverride 800 (
                if userModule.shell == "bash" then pkgs.bash
                else if userModule.shell == "zsh" then pkgs.zsh
                else if userModule.shell == "fish" then pkgs.fish
                else pkgs.bash
              ));
            };
          }
        )
        uniqUsers);

      programs.fish.enable = mkDefault (any (user: hasAttr "shell" users.${user} && users.${user}.shell == "fish") uniqUsers);
      programs.zsh.enable = mkDefault (any (user: hasAttr "shell" users.${user} && users.${user}.shell == "zsh") uniqUsers);
      programs.bash.enable = mkDefault true;

      nix.settings.trusted-public-keys = mkMerge (map (user: mkIf (hasAttr "trustedNixKeys" users.${user}) users.${user}.trustedNixKeys) config.mine.admins);

      home-manager = {
        backupFileExtension = "hmbackup";
        useUserPackages = true;
        useGlobalPkgs = true;

        extraSpecialArgs = {
          inherit inputs;
          inherit self;
          inherit pkgs;

          osConfig = foldl recursiveUpdate { } ([ config ] ++ (map (username: (users."${username}".homeConfigOverwrite or ({ ... }: { }) inputs)) uniqUsers));
        };

        users = mkMerge (map
          (userName:
            let
              userModule = if elem userName uniqUsers then users.${userName} else { };
            in
            {
              "${userName}" =
                { ... }: {
                  imports = [
                    (if elem userName uniqUsers then self.hmModules.default else {
                      # Fake users (service accounts) don't import the full home/*.nix
                      # stack, so they miss the same-value overrides regular users get.
                      programs.ssh.enableDefaultConfig = false;
                      stylix.targets.qt.platform = mkForce "qtct";
                      qt.platformTheme.name = mkForce "adwaita";
                    })
                    (userModule.home or { })
                  ];

                  config = {
                    home.username = mkDefault userName;
                    home.stateVersion = mkDefault config.system.stateVersion;
                  };
                };
            }
          )
          (uniqUsers ++ fakeUsers));
      };
    };
}
