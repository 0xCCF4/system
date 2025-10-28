{ osConfig
, config
, lib
, mine
, pkgs
, ...
}:
with lib; with builtins;
{
  imports = [
    ./traits.nix
    ./persistence.nix
  ];

  options.home.mine.packages = with types;
    let
      isWorkstation = mine.lib.evalMissingOption osConfig "mine.presets.isWorkstation" false;
      traits = config.home.mine.traits;
    in
    {
      cmdlineEssential = mkOption {
        type = bool;
        default = true;
        description = "Install essential command line packages";
      };
      cmdlineExtras = mkOption {
        type = bool;
        default = isWorkstation;
        description = "Install extra command line packages";
      };
      development = mkOption {
        type = bool;
        default = traits.hasDevelopment;
        description = "Install development tools";
      };
      graphicalEssentials = mkOption {
        type = bool;
        default = isWorkstation;
        description = "Install essential graphical packages";
      };
      latex = mkOption {
        type = bool;
        default = traits.hasOffice;
        description = "Install LaTeX";
      };
      jabref = mkOption {
        type = bool;
        default = traits.hasOffice;
        description = "Install JabRef";
      };
      hardwareDesign = mkOption {
        type = bool;
        default = false;
        description = "Install hardware design tools";
      };
      office = mkOption {
        type = bool;
        default = traits.hasOffice;
        description = "Install office tools";
      };
    };

  config =
    with pkgs;
    let
      cfg = config.home.mine.packages;
    in
    {
      home.packages = lists.optionals cfg.cmdlineEssential [
        killall # kill processes by name
        htop # interactive process viewer
        btop # alternative to htop
        dig # DNS lookup
        lsof # list open files
        file # determine file type
        coreutils # basic file utilities
        borgbackup # backup tool
        openssl # cryptographic operations
        wget # download files from the web
      ]
      ++ lists.optionals cfg.cmdlineExtras [
        uutils-coreutils-noprefix
        bat # better cat
        eza # alternative to ls
        fd # alternative to find
        fzf # fuzzy finder
        ripgrep # recursive file content search
        ripgrep-all # ripgrep inside archives
        tokei # count lines of code
        age # simple file encryption
        tldr # show command examples
        just # make replacement
        nh # nixos builder wrapper
        nix-output-monitor # colorful nix build output
        nvd # nix version differ
        graphviz # graph visualization
        presenterm # terminal presentation tool
        ncspot # cli spotify client
        fselect # find files with SQL-like syntax
        zoxide # cd learning tool
        xh # http requests
        dust # du alternative
        dua # directory disk usage analyzer
        yazi # terminal file manager
      ]
      ++ lists.optionals cfg.latex [ texliveFull typst ]
      ++ lists.optionals cfg.jabref [ jabref ]
      ++ lists.optionals cfg.development ([ nixfmt-rfc-style qemu bochs jq ])
      ++ lists.optionals cfg.graphicalEssentials [
        gnome-clocks
        gnome-tweaks
        file-roller
        gnome-calculator
        gnome-screenshot
        gnome-disk-utility
        gnome-system-monitor
        gnome-font-viewer
        eog
        gnome-logs
        gnome-characters
        nautilus
        simple-scan
        evince
        baobab
        keepassxc
        vlc
        gimp
      ]
      ++ lists.optionals cfg.hardwareDesign [
        kicad
        freecad
      ]
      ++ lists.optionals cfg.office [
        libreoffice
        xournalpp
      ];

      home.mine.persistence.cache.directories =
        let
          names = (map (p: p.name) (config.home.packages));
        in
        mkMerge [
          (mkIf (any (n: strings.hasPrefix "keepassxc" n) names) [
            ".config/keepassxc"
            ".cache/keepassxc"
          ])
          (mkIf (any (n: strings.hasPrefix "gimp" n) names) [
            ".config/GIMP"
          ])
          (mkIf (any (n: strings.hasPrefix "borgbackup" n) names) [
            ".config/borg"
            ".cache/borg"
          ])
          (mkIf (any (n: strings.hasPrefix "jabref" n) names) [
            ".local/share/jabref"
            ".java/.userPrefs/org/jabref"
          ])
          (mkIf (any (n: strings.hasPrefix "kicad" n) names) [
            ".config/kicad"
            ".cache/kicad"
            ".local/share/kicad"
          ])
          (mkIf (any (n: strings.hasPrefix "freecad" n) names) [
            ".config/FreeCAD"
            ".cache/FreeCAD"
            ".local/share/FreeCAD"
          ])
        ];
    };
}
