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

      # See the assertions in nixos/hyprland.nix for why this is safe only
      # as long as Flatpak/Linyaps are never installed on this system.
      # xdp-app-info-linyaps.c has the identical bug/fix as
      # xdp-app-info-flatpak.c (it's a near-copy, per its own "this
      # implementation refers to flatpak" comment) -- both need patching,
      # since app-kind detection tries Flatpak, then Snap, then Linyaps
      # before falling back to Host, and each one hard-fails independently
      # on the same /proc/<pid>/root EACCES.
      xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../nixos/xdg-desktop-portal-eacces-fallthrough.patch
          ../nixos/xdg-desktop-portal-eacces-fallthrough-linyaps.patch
        ];
      });
      # todo: need to change this to xdg-desktop-portal-unsafe, then set it inside module to be used instead of normal portal and add assertion checks there
    };
}
