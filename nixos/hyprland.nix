{ lib, config, pkgs, ... }: with lib;
{
  options.mine.desktop.hyprland = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Enable Hyprland desktop environment.";
    };
  };

  config = mkIf config.mine.desktop.hyprland.enable {
    programs.hyprland.enable = mkDefault true;
    programs.hyprlock.enable = mkDefault true;

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    xdg.portal.config.hyprland = {
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
    };

    # Apps that harden themselves against ptrace/memory-dumping via
    # prctl(PR_SET_DUMPABLE, 0) (e.g. Bitwarden desktop, rbw's agent) make
    # their own /proc/<pid> root-owned mode 0500 (proc(5)), which breaks
    # xdg-desktop-portal's Flatpak-detection probe (it needs to open
    # /proc/<pid>/root to look for .flatpak-info) with AccessDenied -- and
    # since that probe hard-fails instead of falling through, EVERY portal
    # call from such an app fails (file choosers, clipboard, ...), with no
    # upstream opt-out (bitwarden/clients#20915, #21749, #22293; the exact
    # portal-side fallthrough fix has already been proposed upstream and
    # rejected: flatpak/xdg-desktop-portal#785, #1490, #1691, #2119 -- a
    # hardened Flatpak app would be indistinguishable from a hardened host
    # app via this check, and would wrongly get host-level portal trust).

    assertions = [
      {
        assertion = !config.services.flatpak.enable;
        message = ''
          The xdg-desktop-portal patch in nixos/hyprland.nix assumes Flatpak
          is never installed on this system -- it can no longer tell a
          hardened host app (e.g. Bitwarden) apart from a hardened Flatpak
          app, and would wrongly grant the latter host-level portal trust.
          Remove the patch (or make it Flatpak-app-aware, e.g. checking
          $XDG_RUNTIME_DIR/.flatpak for a live instance) before enabling
          services.flatpak.enable.
        '';
      }
      {
        assertion = !config.services.linyaps.enable;
        message = ''
          Same issue as the services.flatpak.enable assertion above, for
          Linyaps instead of Flatpak.
        '';
      }
    ];
  };
}
