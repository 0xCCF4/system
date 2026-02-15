{ ... }: {
  imports = [
    ../persistence.nix
  ];

  config = {
    home.mine.persistence.cache.files = [
      ".local/share/gnome-shell/session-active-history.json"
    ];

    dconf.settings = {
      "org/gnome/desktop/break-reminders" = {
        selected-breaks = [ "eyesight" "momvement" ];
      };
      "org/gnome/desktop/break-reminders/movement" = {
        duration-seconds = 300;
        interval-seconds = 1800;
      };
      "org/gnome/desktop/break-reminders/eyesight".play-sound = true;
      "org/gnome/desktop/break-reminders/movement".play-sound = true;
      "org/gnome/desktop/screen-time-limits".daily-limit-enabled = true;
    };
  };
}
