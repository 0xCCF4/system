{ inputs, lib, ... }: with lib; with builtins; let
  modules = removeAttrs (inputs.noxa.lib.nixDirectoryToAttr' ../users) [ "default" ];
  modulesExternal = removeAttrs (inputs.noxa.lib.nixDirectoryToAttr' ../external/users) [ "default" ];
  uidMapping = fromJSON (readFile ../users/_mapping.json);
  uidExternalMapping = fromJSON (readFile ../external/users/_mapping.json);

  uidMappingAll = recursiveUpdate uidMapping (if (pathExists ../external/users) then uidExternalMapping else { });

  users = mapAttrs
    (name: module: (import module inputs) // {
      uid = uidMappingAll.${name} or (throw "No UID mapping for user: ${name}");
    })
    modules;
  usersExternal = mapAttrs
    (name: module: (import module inputs) // {
      uid = uidMappingAll.${name} or (throw "No UID mapping for user: ${name}");
    })
    modulesExternal;

  allUserNames = lists.unique (attrNames users ++ attrNames usersExternal);

  allUsers = (mkMerge (map
    (name: {
      "${name}" = {
        description = usersExternal.${name}.description or users.${name}.description;
        authorizedKeys = (usersExternal.${name}.authorizedKeys or [ ]) ++ (users.${name}.authorizedKeys or [ ]);
        shell = usersExternal.${name}.shell or users.${name}.shell;
        hashedPassword = usersExternal.${name}.hashedPassword or users.${name}.hashedPassword;
        trustedNixKeys = usersExternal.${name}.trustedNixKeys or users.${name}.trustedNixKeys;
        home = { ... }: {
          imports = [ usersExternal.${name}.home ] ++ [ users.${name}.home ];
        };
        os = { ... }: {
          imports = [ usersExternal.${name}.os ] ++ [ users.${name}.os ];
        };
      };
    })
    allUserNames)).contents;
in
{
  flake = {
    users = if (pathExists ../external/users) then allUsers else users;
  };
}
