{ pkgs
, lib
, config
, noxa
, options
, ...
}:
with lib;
let
in
{
  options.mine.storeSign = with types; {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Sign derivations build on the local machine.";
    };
  };

  config = mkIf (config.mine.storeSign.enable && config.noxa.secrets.enable)
    {
      # nix sign-paths --all -k  {private_key}

      noxa.secrets.def = [
        {
          ident = "nixos-store-signing-key";
          module = "mine.storeSign";
          generator.script = "nix-store-key";
        }
      ];

      nix.settings.secret-key-files = mkIf (!config.age.rekey.initialRollout) (
        config.age.secrets.${noxa.lib.secrets.computeIdentifier {
          ident = "nixos-store-signing-key";
          module = "mine.storeSign";
        }}.path
      );
    };
}
