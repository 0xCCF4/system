{ pkgs
, config
, lib
, ...
}:
with lib; with builtins;
{
  options.mine.locale = with types;
    {
      language = mkOption {
        type = str;
        default = "en_US.UTF-8";
        description = "The language to use for the system.";
      };
      formatLanguage = mkOption {
        type = str;
        default = "de_DE.UTF-8";
        description = "The language to use for the system.";
      };
      timeZone = mkOption {
        type = str;
        default = "Europe/Berlin";
        description = "The time zone to use for the system.";
      };
      keyboardLayout = mkOption {
        type = str;
        default = "us";
        description = "The keyboard layout to use for the system.";
      };
      keyboardVariant = mkOption {
        type = str;
        default = "de_se_fi,nodeadkeys";
        description = "The keyboard variant to use for the system.";
      };
    };

  config =
    let
      cfg = config.mine.locale;
    in
    {
      time.timeZone = mkDefault cfg.timeZone;
      i18n.defaultLocale = mkDefault cfg.language;
      i18n.extraLocaleSettings = {
        LC_ADDRESS = mkDefault cfg.formatLanguage;
        LC_IDENTIFICATION = mkDefault cfg.formatLanguage;
        LC_MEASUREMENT = mkDefault cfg.formatLanguage;
        LC_MONETARY = mkDefault cfg.formatLanguage;
        LC_NAME = mkDefault cfg.formatLanguage;
        LC_NUMERIC = mkDefault cfg.formatLanguage;
        LC_PAPER = mkDefault cfg.formatLanguage;
        LC_TELEPHONE = mkDefault cfg.formatLanguage;
        LC_TIME = mkDefault cfg.formatLanguage;
      };
      services.xserver.xkb = {
        layout = mkDefault cfg.keyboardLayout;
        variant = mkDefault cfg.keyboardVariant;
      };
      console.keyMap = mkDefault cfg.keyboardLayout;
    };
}
