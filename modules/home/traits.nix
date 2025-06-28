{ osConfig
, lib
, config
, mine
, ...
}: with lib; with builtins;
{
  options.home.mine.traits = with types;
    let
      cfg = config.home.mine.traits;
    in
    {
      traits = mkOption {
        type = listOf (
          enum [
            "development"
            "gaming"
            "office"
          ]
        );
        default = [ ];
        description = "Application presets. Install packages and configure services based on the selected traits.";
      };
      hasDevelopment = mkOption {
        type = bool;
        default = elem "development" cfg.traits;
        readOnly = true;
      };
      hasGaming = mkOption {
        type = bool;
        default = elem "gaming" cfg.traits;
        readOnly = true;
      };
      hasOffice = mkOption {
        type = bool;
        default = elem "office" cfg.traits;
        readOnly = true;
      };
    };

  config =
    {
      assertions = [
        {
          assertion = config.home.mine.traits.traits == [ ] || (mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" true);
          message = "Traits can only be set for workstations.";
        }
      ];
    };
}
