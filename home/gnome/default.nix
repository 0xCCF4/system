{ config
, pkgs
, lib
, self
, osConfig
, ...
}:
with lib;
let
  gruvboxPlus = pkgs.callPackage ./gruvbox-plus.nix { };

  usage = inputs.nixos.modules.nixos.usage;
in
{
  imports = [
    ../persistence.nix
  ];

  options.home.mine = {
    gnome.vitals = lib.mkOption {
      type = lib.types.bool;
      default = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
      description = "Enable vitals extension";
    };
    gnome.spaceBar = lib.mkOption {
      type = lib.types.bool;
      default = self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
      description = "Enable space-bar extension";
    };
  };

  config = mkIf osConfig.services.desktopManager.gnome.enable {
    home.mine.persistence.cache.files = [
      ".config/monitors.xml"
    ];

    gtk =
      {
        enable = true;
        #theme.package = pkgs.adw-gtk3;
        theme.name = "adw-gtk3";

        cursorTheme.package = pkgs.adw-gtk3;
        cursorTheme.name = "Adwaita";
        #cursorTheme.size = gnome.cursorSize;

        iconTheme.package = gruvboxPlus;
        iconTheme.name = "GruvboxPlus";
      };

    dconf.settings = {
      "org/gnome/mutter" = {
        edge-tiling = true;
      };
      "org/gnome/desktop/interface" = {
        enable-hot-corners = true;
        show-battery-percentage = true;
      };
      "org/gnome/shell" = {
        favorite-apps = [
          "firefox.desktop"
          "org.gnome.Nautilus.desktop"
          "alacritty.desktop"
        ];
        # enabled-extensions = mkMerge [
        #   [
        #     # "drive-menu@gnome-shell-extensions.gcampax.github.com"
        #     "appindicatorsupport@rgcjonas.gmail.com"
        #   ]
        #   (lists.optional gnome.vitals "Vitals@CoreCoding.com")
        #   (lists.optional gnome.spaceBar "space-bar@luchrioh")
        # ];
      };
      "org/gnome/desktop/wm/preferences" = {
        workspace-names = [ "Main" ];
      };
      "org/gnome/desktop/screensaver" = {
        color-shading-type = "solid";
      };
      "org/gnome/shell/extensions/vitals" = {
        hot-sensors = [
          "_processor_usage_"
          "_memory_usage_"
          "__temperature_avg__"
          "__network-rx_max__"
          "__network-tx_max__"
          "_storage_free_"
          "_network_public_ip_"
        ];
      };
    };

    xdg.mimeApps.defaultApplications = {
      "application/pdf" = [ "org.gnome.Evince.desktop" "firefox.desktop" ];
      "image/jpeg" = [ "org.gnome.eog.desktop" ];
      "image/png" = [ "org.gnome.eog.desktop" ];
    };
    xdg.mimeApps.associations.added = {
      "application/pdf" = [ "org.gnome.Evince.desktop" "firefox.desktop" ];
      "image/jpeg" = [ "org.gnome.eog.desktop" ];
      "image/png" = [ "org.gnome.eog.desktop" ];
    };

    # home.packages = with pkgs.gnomeExtensions; [
    #   appindicator
    #   vitals
    #   # sound-output-device-chooser
    #   space-bar
    # ];

    home.file = {
      ".local/share/icons/GruvboxPlus".source = "${gruvboxPlus}/Gruvbox-Plus-Dark";
    };
  };
}
