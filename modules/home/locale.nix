{ config
, lib
, mine
, osConfig
, ...
}:
with lib; with builtins;
{
  options.home.mine.locale = with types;
    {
      language = mkOption {
        type = str;
        default = mine.lib.evalMissingOption osConfig "mine.locale.language" "en_US.UTF-8";
        description = "The language to use for the system.";
      };
      formatLanguage = mkOption {
        type = str;
        default = mine.lib.evalMissingOption osConfig "mine.locale.formatLanguage" "de_DE.UTF-8";
        description = "The language to use for the system.";
      };
    };

  config =
    let
      cfg = config.home.mine.locale;
    in
    {
      home.language = {
        base = cfg.language;
        address = cfg.formatLanguage;
        collate = cfg.formatLanguage;
        measurement = cfg.formatLanguage;
        monetary = cfg.formatLanguage;
        name = cfg.formatLanguage;
        numeric = cfg.formatLanguage;
        paper = cfg.formatLanguage;
        telephone = cfg.formatLanguage;
        time = cfg.formatLanguage;
      };
    };
}
