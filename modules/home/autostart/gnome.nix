{ config, osConfig, lib, ... }: with lib; with builtins;
let
  cfg = config.home.mine.autostart;
in
{
  config = mkIf osConfig.mine.desktop.gnome.enable {
    home.file =
      (listToAttrs (
        map
          (pkg: {
            name = ".config/autostart/" + pkg.pname + ".desktop";
            value =
              if pkg ? desktopItem then
                {
                  # Application has a desktopItem entry.
                  # Assume that it was made with makeDesktopEntry, which exposes a
                  # text attribute with the contents of the .desktop file
                  text = pkg.desktopItem.text;
                }
              else
                {
                  # Application does *not* have a desktopItem entry. Try to find a
                  # matching .desktop name in /share/applications
                  source =
                    let
                      appsPath = "${pkg}/share/applications";
                      # function to filter out subdirs of /share/applications
                      filterFiles =
                        dirContents:
                        attrsets.filterAttrs
                          (
                            _: fileType:
                            elem fileType [
                              "regular"
                              "symlink"
                            ]
                          )
                          dirContents;
                    in
                    (
                      # if there's a desktop file by the app's pname, use that
                      if (pathExists "${appsPath}/${pkg.pname}.desktop") then
                        "${appsPath}/${pkg.pname}.desktop"
                      # if there's not, find the first desktop file in the app's directory and assume that's good enough
                      else
                        (
                          if pathExists "${appsPath}" then
                            "${appsPath}/${head (attrNames (filterFiles (readDir "${appsPath}")))}"
                          else
                            with noxa.lib.ansi; throw "${fgYellow}Selected ${fgCyan}'${pkg.pname}'${fgYellow} for autostart but it does not expose a ${fgCyan}.desktop${fgYellow} file. Please wrap the package in a new one and export a desktop file using ${fgCyan+italic}makeDesktopItem${fgYellow+noItalic}.${reset}"
                        )
                    );
                };
          })
          config.home.mine.autostart
      ));
  };
}
