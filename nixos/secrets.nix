{ noxa, lib, config, ... }: with lib; {

  config = {
    noxa.sshHostKeys.generate = true;

    noxa.secrets.options.masterIdentities = [
      {
        identity = "/home/mx/Documents/system/external/private/secrets/master.age";
        pubkey = "age139u6cdr527jm5x4e3fffqpd76gewwydlz2ekgr78n6yffeh3ce3q0mk2ma";
      }
    ];
    noxa.secrets.secretsPath = mkIf (config.noxa.secrets.enable) (
      let
        path = ./../external/private/secrets;
      in
      if pathExists path then path else with noxa.lib.ansi; throw "${fgRed}The secrets path ${fgCyan+toString path+fgRed} was not found. Did you run with ${fgCyan}?submodules=1${fgRed}, or did you just cloned this repo? ${fgYellow}Suggestion: Change ${fgCyan}noxa.secrets.secretsPath${fgYellow} to another path.${reset}"
    );
  };
}
