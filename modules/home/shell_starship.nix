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
      enable = true;
      settings = {
        "$schema" = "https://starship.rs/config-schema.json";

        format = lib.concatStrings [
          "[](base09)"
          #"$os"
          "$sudo"
          "$username"
          "[](bg:base0A fg:base09)"
          "$directory"
          "$nix_shell"
          #"[](fg:base09 bg:base0C)"
          #"$git_branch"
          #"$git_status"
          "$custom"
          "[](fg:base00 bg:base01)"
          #"$c"
          #"$cpp"
          #"$rust"
          #"[](fg:base0D bg:base02)"
          #"$docker_context"
          #"$conda"
          #"$pixi"
          #"$nix_shell"
          #"[](fg:base02 bg:base01)"
          "$time"
          "[ ](fg:base01)"
          "$line_break$character"
        ];

        os = {
          disabled = false;
          style = "bg:base09 fg:base07";

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
          style_user = "bg:base09 fg:base07";
          style_root = "bg:base09 fg:base07";
          format = "[ $user ]($style)";
        };

        directory = {
          style = "fg:base07 bg:base0A";
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
          style = "bg:base0C";
          format = "[[ $symbol $branch ](fg:base07 bg:base0C)]($style)";
        };

        git_status = {
          disabled = false;
          style = "bg:base0C";
          format = "[[($all_status$ahead_behind )](fg:base07 bg:base0C)]($style)";
        };

        # custom module for jj status
        custom.jj = {
          ignore_timeout = true;
          description = "The current jj status";
          detect_folders = [ ".jj" ];
          format = "[[ $symbol $output ](fg:base07 bg:base0C)]($style)";
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
          style = "bg:base09 fg:base07";
          format = "[[[](bg:base08 fg:base09) $symbol [](bg:base09 fg:base08)](fg:base07 bg:base08)]($style)";
          disabled = false;
        };

        nodejs = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        c = {
          symbol = " ";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        cpp = {
          symbol = " ";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        rust = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        golang = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        php = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        java = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        kotlin = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        haskell = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        python = {
          symbol = "";
          style = "bg:base0D";
          format = "[[ $symbol( $version) ](fg:base07 bg:base0D)]($style)";
        };

        docker_context = {
          symbol = "";
          style = "bg:base02";
          format = "[[ $symbol( $context) ](fg:#83a598 bg:base02)]($style)";
        };

        conda = {
          style = "bg:base02";
          format = "[[ $symbol( $environment) ](fg:#83a598 bg:base02)]($style)";
        };

        pixi = {
          style = "bg:base02";
          format = "[[ $symbol( $version)( $environment) ](fg:base07 bg:base02)]($style)";
        };

        nix_shell = {
          symbol = "❄️ ";
          style = "bg:base02";
          format = "[ via [$symbol$state( \($name\))]($style)";
        };

        time = {
          disabled = false;
          time_format = "%R";
          style = "bg:base01";
          format = "[[  $time ](fg:base07 bg:base01)]($style)";
        };

        line_break = {
          disabled = false;
        };

        character = {
          disabled = false;
          success_symbol = "[](bold fg:base0B)";
          error_symbol = "[](bold fg:base08)";
          vimcmd_symbol = "[](bold fg:base0B)";
          vimcmd_replace_one_symbol = "[](bold fg:base0E)";
          vimcmd_replace_symbol = "[](bold fg:base0E)";
          vimcmd_visual_symbol = "[](bold fg:base0A)";
        };
      };
    };
  };
}
