{ inputs, withSystem, ... }: {
  flake.overlays.default = final: prev:
    (withSystem prev.system ({ config, ... }: config.packages))
    // {
      timetrax = inputs.timetrax.packages.${prev.system}.default;
      frostx = inputs.frostx.packages.${prev.system}.default;
      zrb = inputs.zrb.packages.${prev.system}.default;
    };
}
