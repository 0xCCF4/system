{ config
, lib
, ...
}:
with lib;
{
  config = {
    zramSwap = {
      enable = mkDefault true;
      algorithm = mkDefault "zstd";
      memoryPercent = mkDefault 50;
    };

    boot.kernel.sysctl."vm.swappiness" = mkIf (config.zramSwap.enable) (mkDefault 180);
    boot.kernel.sysctl."vm.page-cluster" = mkIf (config.zramSwap.enable) (mkDefault 0);
  };
}
