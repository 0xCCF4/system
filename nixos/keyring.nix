{ config, lib, ... }:
with lib;
{
  config = mkIf config.mine.presets.isWorkstation {
    services.gnome.gnome-keyring.enable = mkDefault true;
  };
}
