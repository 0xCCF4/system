{ inputs
, pkgs
, lib
, config
, options
, ...
}:
with lib;
{
  options.mine.age.fix = with types;  mkOption {
    type = bool;
    default = (hasAttr "age" options) && (length (attrNames config.age.secrets)) > 0;
    description = "Apply agenix bugfix: delete /run/agenix before activation script runs.";
  };

  config = mkIf config.mine.age.fix {
    system.activationScripts.agenixBugfix = {
      text = ''
        echo "[agenix] deleting ${config.age.secretsDir} to workaround agenix bug"
        rm -f "${config.age.secretsDir}"
      '';
      deps = [ "specialfs" ];
    };
    system.activationScripts.agenixNewGeneration = {
      deps = [ "agenixBugfix" ];
    };
  };
}
