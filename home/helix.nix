{ config
, pkgs
, lib
, self
, osConfig
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
      home.packages =
        mkIf
          (
            config.programs.helix.enable
            && (self.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false)
          )
          [
            pkgs.tinymist
            pkgs.bash-language-server
            pkgs.texlab
            pkgs.bibtex-tidy
            pkgs.yaml-language-server
            pkgs.docker-compose-language-service
            pkgs.fish-lsp
            pkgs.vscode-json-languageserver
            pkgs.markdown-oxide
            pkgs.nil
            pkgs.nixd
            pkgs.taplo
            pkgs.metals
          ];

      # MANPAGER = "sh -c 'col -bx | hx'";
      # MANWIDTH = 87;
      # MANROFFOPT = "-c";

      programs.helix = {
        enable = mkDefault true;
        defaultEditor = mkDefault true;
        extraPackages = with pkgs; [ marksman ];
        # Enable helix-view's "term" cargo feature so the OSC52 (Termcode)
        # clipboard provider is compiled in; nixpkgs' evil-helix build omits
        # it by default, which silently breaks clipboard writes over SSH.
        package = pkgs.evil-helix.overrideAttrs (old: {
          buildFeatures = (old.buildFeatures or [ ]) ++ [ "helix-view/term" ];
        });
        settings = {
          editor = {
            mouse = false;
            clipboard-provider = "termcode";

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

            # vim substitute: delete selection, drop into insert mode
            "s" = [
              "delete_selection"
              "insert_mode"
            ];

            # yank/paste through the system clipboard (OSC52) instead of
            # Helix's internal register, matching vim's clipboard=unnamedplus
            "y" = "yank_to_clipboard";
            "p" = "paste_clipboard_after";
            "P" = "paste_clipboard_before";
          };
        };
      };
    };
}
