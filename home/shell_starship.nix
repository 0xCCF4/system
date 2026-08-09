{ inputs
, config
, pkgs
, lib
, ...
}:

let
  colors = config.lib.stylix.colors;

  # Base16 neutral shades
  black = colors.withHashtag.base00;
  black1 = colors.withHashtag.base01;
  black2 = colors.withHashtag.base02;
  black3 = colors.withHashtag.base03;
  black4 = colors.withHashtag.base04;

  white = colors.withHashtag.base05;
  white1 = colors.withHashtag.base06;
  white2 = colors.withHashtag.base07;

  # Base16 semantic colors
  red = colors.withHashtag.base08;
  orange = colors.withHashtag.base09;
  yellow = colors.withHashtag.base0A;
  green = colors.withHashtag.base0B;
  cyan = colors.withHashtag.base0C;
  blue = colors.withHashtag.base0D;
  purple = colors.withHashtag.base0E;
  brown = colors.withHashtag.base0F;
in

{
  config = {
    programs.starship = {
      enable = true;

      settings = {
        "$schema" = "https://starship.rs/config-schema.json";

        format = lib.concatStrings [
          "[](${orange})"
          # "$os"
          "$sudo"
          "$username"
          "[](bg:${black} fg:${orange})"
          "$directory"
          # "$nix_shell"
          "$hostname"
          # "[](fg:${orange} bg:${cyan})"
          # "$git_branch"
          # "$git_status"
          "$custom"
          "[](fg:${black} bg:${black1})"
          # "$c"
          # "$cpp"
          # "$rust"
          # "[](fg:${blue} bg:${black2})"
          # "$docker_context"
          # "$conda"
          # "$pixi"
          # "$nix_shell"
          # "[](fg:${black2} bg:${black1})"
          "$time"
          "[ ](fg:${black1})"
          "$line_break$character"
        ];

        os = {
          disabled = false;
          style = "bg:${orange} fg:${white2}";

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
          style_user = "bg:${orange} fg:${white2}";
          style_root = "bg:${orange} fg:${white2}";
          format = "[ $user ]($style)";
        };

        directory = {
          style = "fg:${white2} bg:${black}";
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
          style = "bg:${cyan}";
          format = "[[ $symbol $branch ](fg:${purple} bg:${black})]($style)";
        };

        git_status = {
          disabled = false;
          style = "bg:${cyan}";
          format = "[[($all_status$ahead_behind )](fg:${purple} bg:${black})]($style)";
        };

        # Custom module for jj status
        custom.jj = {
          ignore_timeout = true;
          description = "The current jj status";
          detect_folders = [ ".jj" ];
          format = "[[ $symbol $output ](fg:${purple} bg:${black})]($style)";
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
          style = "bg:${orange} fg:${white2}";

          format =
            "[[[](bg:${red} fg:${orange}) $symbol [](bg:${orange} fg:${red})](fg:${white2} bg:${red})]($style)";

          disabled = false;
        };

        nodejs = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        c = {
          symbol = " ";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        cpp = {
          symbol = " ";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        rust = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        golang = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        php = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        java = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        kotlin = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        haskell = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        python = {
          symbol = "";
          style = "bg:${blue}";
          format = "[[ $symbol( $version) ](fg:${white2} bg:${blue})]($style)";
        };

        docker_context = {
          symbol = "";
          style = "bg:${black2}";
          format = "[[ $symbol( $context) ](fg:${cyan} bg:${black2})]($style)";
        };

        conda = {
          style = "bg:${black2}";
          format = "[[ $symbol( $environment) ](fg:${cyan} bg:${black2})]($style)";
        };

        pixi = {
          style = "bg:${black2}";
          format = "[[ $symbol( $version)( $environment) ](fg:${white2} bg:${black2})]($style)";
        };

        nix_shell = {
          disable = true;
          symbol = "❄️ ";
          style = "bg:${black2}";
          format = "[ via [$symbol$state( \\($name\\))]($style)";
        };

        hostname = {
          ssh_only = false;
          detect_env_vars = [ "!TMUX" "SSH_CONNECTION" ];
          style = "bg:${black} fg:${cyan}";
          format = "[@ $hostname ]($style)";
        };

        time = {
          disabled = false;
          time_format = "%R";
          style = "bg:${black1}";
          format = "[[  $time ](fg:${white2} bg:${black1})]($style)";
        };

        line_break = {
          disabled = false;
        };

        character = {
          disabled = false;

          success_symbol = "[](bold fg:${green})";
          error_symbol = "[](bold fg:${red})";
          vimcmd_symbol = "[](bold fg:${green})";
          vimcmd_replace_one_symbol = "[](bold fg:${purple})";
          vimcmd_replace_symbol = "[](bold fg:${purple})";
          vimcmd_visual_symbol = "[](bold fg:${yellow})";
        };
      };
    };
  };
}
