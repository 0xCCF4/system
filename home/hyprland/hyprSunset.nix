{ pkgs, lib, config, osConfig, ... }: with pkgs; with builtins; with lib; {
  config = {
    services.hyprsunset = {
      enable = mkDefault osConfig.programs.hyprlock.enable;

      settings = {
        profile = [
          {
            time = "7:30";
            identity = true;
          }
          {
            time = "20:00";
            temperature = 5000;
            gamma = 0.8;
          }
        ];
      };
    };
  };
}
