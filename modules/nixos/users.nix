{ lib, config, pkgs, ... }: with lib; with builtins; {
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
        hashedPasswordFile = mkDefault "/pass/${submodule.config.name}.hashed-password";
      };
    }));
  };

  config =
    let
      spec = mapAttrsToList
        (_: u: ''
          echo "[users] creating hashed password file for user: ${escapeShellArg u.name}"
          cat ${escapeShellArg u.passwordFileOverride} | ${pkgs.mkpasswd}/bin/mkpasswd -s -m sha512crypt > ${escapeShellArg u.hashedPasswordFile}
        '')
        (filterAttrs (_: u: u.passwordFileOverride != null) config.users.users);
    in
    mkIf (!config.age.rekey.initialRollout) {
      system.activationScripts.usersPre = {
        supportsDryActivation = true;
        text = concatStringsSep "\n" ([
          ''
            OLD_UMASK=$(umask)
            install -m 700 -d /pass/
            umask 600
          ''
        ] ++ spec ++ [
          ''
            umask $OLD_UMASK
          ''
        ]);
        deps = [ "agenix" "agenixInstall" "agenixChown" ];
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
