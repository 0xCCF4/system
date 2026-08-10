{ inputs, self, ... }: {
  flake.overlays.default = final: prev:
    self.packages.${final.system}
    // {
      timetrax = inputs.timetrax.packages.${final.system}.default;
      frostx = inputs.frostx.packages.${final.system}.default;
      zrb = inputs.zrb.packages.${final.system}.default;
    };
}
