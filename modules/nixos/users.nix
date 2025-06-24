{ lib, config, ... }: with lib; with builtins; {
  options.users.users = with types; mkOption {
    type = attrsOf (submodule (submodule: {
      options.passwordFileOverride = mkOption {
        type = nullOr str;
        description = ''
          Path to a file containing the user's password. If set, this will override
          the default password setting mechanism.
        '';
        default = null;
      };

      config = mkIf (submodule.config.passwordFileOverride != null) {
        hashedPasswordFile = "/pass/${submodule.config.name}.hashed-password";
      };
    }));
  };

  config =
    let
      spec = mapAttrsToList
        (_: u: ''
          cat ${escapeShellArg u.passwordFileOverride} | mkpasswd -s -m sha512crypt > ${escapeShellArg u.hashedPasswordFile}
        '')
        (filterAttrs (_: u: u.passwordFileOverride != null) config.users.users);
    in
    {
      system.activationScripts.usersPre = {
        supportsDryActivation = true;
        text = concatStringsSep "\n" ([
          ''
            install -m 700 -d /pass/
            umask u=rw
          ''
        ] ++ spec);
      };
      system.activationScripts.users.deps = [ "usersPre" ];
      system.activationScripts.usersPost = {
        deps = [ "usersPre" "users" ];
        supportsDryActivation = true;
        text = ''
          rm -Rf /pass
        '';
      };
    };
}
