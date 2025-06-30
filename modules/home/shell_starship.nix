{ inputs
, config
, pkgs
, lib
, ...
}:
with lib; with builtins;
{
  config = {
    programs.starship = {
      enable = mkDefault true;
      settings = mkDefault {
        "$schema" = "https://starship.rs/config-schema.json";

        format = lib.concatStrings [
          "[](color_orange)"
          "$os"
          "$sudo"
          "$username"
          "[](bg:color_yellow fg:color_orange)"
          "$directory"
          "$nix_shell"
          "[](fg:color_yellow bg:color_aqua)"
          "$git_branch"
          "$git_status"
          "$custom"
          "[](fg:color_aqua bg:color_blue)"
          "$c"
          "$cpp"
          "$rust"
          "[](fg:color_blue bg:color_bg3)"
          "$docker_context"
          "$conda"
          "$pixi"
          "$nix_shell"
          "[](fg:color_bg3 bg:color_bg1)"
          "$time"
          "[ ](fg:color_bg1)"
          "$line_break$character"
        ];

        palette = "gruvbox_dark";

        palettes.gruvbox_dark = {
          color_fg0 = "#fbf1c7";
          color_bg1 = "#3c3836";
          color_bg3 = "#665c54";
          color_blue = "#458588";
          color_aqua = "#689d6a";
          color_green = "#98971a";
          color_orange = "#d65d0e";
          color_purple = "#b16286";
          color_red = "#cc241d";
          color_yellow = "#d79921";
        };

        os = {
          disabled = false;
          style = "bg:color_orange fg:color_fg0";

          symbols = {
            Windows = "󰍲";
            Ubuntu = "󰕈";
            SUSE = "";
            Raspbian = "󰐿";
            Mint = "󰣭";
            Macos = "󰀵";
            Manjaro = "";
            Linux = "󰌽";
            Gentoo = "󰣨";
            Fedora = "󰣛";
            Alpine = "";
            Amazon = "";
            Android = "";
            Arch = "󰣇";
            Artix = "󰣇";
            EndeavourOS = "";
            CentOS = "";
            Debian = "󰣚";
            Redhat = "󱄛";
            RedHatEnterprise = "󱄛";
            Pop = "";
          };
        };

        username = {
          show_always = true;
          style_user = "bg:color_orange fg:color_fg0";
          style_root = "bg:color_orange fg:color_fg0";
          format = "[ $user ]($style)";
        };

        directory = {
          style = "fg:color_fg0 bg:color_yellow";
          format = "[ $path ]($style)";
          truncation_length = 3;
          truncation_symbol = "…/";

          substitutions = {
            "Documents" = "󰈙 ";
            "Downloads" = " ";
            "Music" = "󰝚 ";
            "Pictures" = " ";
            "Developer" = "󰲋 ";
          };
        };

        git_branch = {
          disabled = false;
          symbol = "";
          style = "bg:color_aqua";
          format = "[[ $symbol $branch ](fg:color_fg0 bg:color_aqua)]($style)";
        };

        git_status = {
          disabled = false;
          style = "bg:color_aqua";
          format = "[[($all_status$ahead_behind )](fg:color_fg0 bg:color_aqua)]($style)";
        };

        # custom module for jj status
        custom.jj = {
          ignore_timeout = true;
          description = "The current jj status";
          detect_folders = [ ".jj" ];
          format = "[[ $symbol $output ](fg:color_fg0 bg:color_aqua)]($style)";
          symbol = "";
          command = ''
            jj log --revisions @ --no-graph --ignore-working-copy --color never --limit 1 --template '
              separate(" ",
                concat(
                  change_id.shortest(4).prefix(),
                  if(change_id.shortest(4).rest(), ":"),
                  change_id.shortest(4).rest(),
                ),
                bookmarks,
                "|",
                concat(
                  if(conflict, "💥"),
                  if(divergent, "🚧"),
                  if(hidden, "👻"),
                  if(immutable, "🔒"),
                ),
                if(empty, "(empty)"),
                coalesce(
                  truncate_end(29, description.first_line(), "…"),
                  "(no description set)",
                ),
              )
            '
          '';
        };

        sudo = {
          symbol = "";
          style = "bg:color_orange fg:color_fg0";
          format = "[[[](bg:color_red fg:color_orange) $symbol [](bg:color_orange fg:color_red)](fg:color_fg0 bg:color_red)]($style)";
          disabled = false;
        };

        nodejs = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        c = {
          symbol = " ";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        cpp = {
          symbol = " ";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        rust = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        golang = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        php = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        java = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        kotlin = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        haskell = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        python = {
          symbol = "";
          style = "bg:color_blue";
          format = "[[ $symbol( $version) ](fg:color_fg0 bg:color_blue)]($style)";
        };

        docker_context = {
          symbol = "";
          style = "bg:color_bg3";
          format = "[[ $symbol( $context) ](fg:#83a598 bg:color_bg3)]($style)";
        };

        conda = {
          style = "bg:color_bg3";
          format = "[[ $symbol( $environment) ](fg:#83a598 bg:color_bg3)]($style)";
        };

        pixi = {
          style = "bg:color_bg3";
          format = "[[ $symbol( $version)( $environment) ](fg:color_fg0 bg:color_bg3)]($style)";
        };

        nix_shell = {
          symbol = "❄️ ";
          style = "bg:color_bg3";
          format = "[ via [$symbol$state( \($name\))]($style)";
        };

        time = {
          disabled = false;
          time_format = "%R";
          style = "bg:color_bg1";
          format = "[[  $time ](fg:color_fg0 bg:color_bg1)]($style)";
        };

        line_break = {
          disabled = false;
        };

        character = {
          disabled = false;
          success_symbol = "[](bold fg:color_green)";
          error_symbol = "[](bold fg:color_red)";
          vimcmd_symbol = "[](bold fg:color_green)";
          vimcmd_replace_one_symbol = "[](bold fg:color_purple)";
          vimcmd_replace_symbol = "[](bold fg:color_purple)";
          vimcmd_visual_symbol = "[](bold fg:color_yellow)";
        };
      };
    };
  };
}
