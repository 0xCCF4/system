{ inputs, withSystem, ... }: {
  flake.overlays.default =
    final: prev:
    let
      system = prev.stdenv.hostPlatform.system;
    in
    (withSystem system ({ config, ... }: config.packages))
    // {
      timetrax = inputs.timetrax.packages.${system}.default;
      frostx = inputs.frostx.packages.${system}.default;
      zrb = inputs.zrb.packages.${system}.default;

      waybar = prev.waybar.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./patches/waybar-mpris-ellipsize.patch
          ./patches/waybar-battery-no-charging-tint.patch
        ];
      });
    };
}
