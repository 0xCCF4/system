{ config, lib, noxa, pkgs, ... }: with lib; {

  imports = noxa.lib.nixDirectoryToList ./.;

  options.mine.desktop.gnome = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable GNOME desktop environment.";
    };
  };

  config =
    let
      cfg = config.mine.desktop.gnome;
    in
    mkIf cfg.enable {
      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;

      services.gnome.core-apps.enable = false;
      environment.gnome.excludePackages = with pkgs; [
        baobab
        cheese
        eog
        epiphany
        gedit
        simple-scan
        totem
        yelp
        evince
        file-roller
        geary
        seahorse
        gnome-calculator
        gnome-calendar
        gnome-characters
        gnome-clocks
        gnome-contacts
        gnome-font-viewer
        gnome-logs
        gnome-maps
        gnome-music
        gnome-photos
        gnome-screenshot
        gnome-system-monitor
        gnome-weather
        gnome-disk-utility
        gnome-connections
        gnome-tour
        xterm
      ];
    };
}
