{ config
, pkgs
, lib
, ...
}:
with lib;
{
  config =
    let
      helix = config.modules.home.helix;
      colors = config.colorScheme.palette;
    in
    {
      programs.helix = {
        enable = mkDefault true;
        defaultEditor = mkDefault true;
        extraPackages = with pkgs; [ marksman ];
        package = pkgs.evil-helix;
        settings = {
          theme = "serika-dark";
          editor = {
            mouse = false;

            cursor-shape.normal = "block";
            cursor-shape.insert = "bar";
            cursor-shape.select = "underline";

            file-picker.hidden = false;

            statusline = {
              left = [
                "mode"
                "spinner"
                "file-name"
              ];
              center = [ ];
              right = [
                "version-control"
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "│";
              mode.normal = "NORMAL";
              mode.insert = "INSERT";
              mode.select = "SELECT";
            };

            indent-guides = {
              render = true;
              charactor = "▏";
              skip-levels = 1;
            };
          };

          keys.normal = {
            "A-up" = [
              "extend_to_line_bounds"
              "delete_selection"
              "move_line_up"
              "paste_before"
            ];
            "A-down" = [
              "extend_to_line_bounds"
              "delete_selection"
              "paste_after"
            ];
          };
        };
      };
    };
}
