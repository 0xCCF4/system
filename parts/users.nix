{ inputs, lib, ... }: with lib; with builtins; let
  modules = removeAttrs (inputs.noxa.lib.nixDirectoryToAttr' ../users) [ "default" ];
  modulesExternal = removeAttrs (inputs.noxa.lib.nixDirectoryToAttr' ../external/private/users) [ "default" ];
  uidMapping = fromJSON (readFile ../users/_mapping.json);
  uidExternalMapping = fromJSON (readFile ../external/private/users/_mapping.json);

  uidMappingAll = recursiveUpdate uidMapping (if (pathExists ../external/private/users/_mapping.json) then uidExternalMapping else { });

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

  allUsers = listToAttrs
    (map
      (name: nameValuePair name {
        description = usersExternal.${name}.description or users.${name}.description or "No description provided.";
        authorizedKeys = (usersExternal.${name}.authorizedKeys or [ ]) ++ (users.${name}.authorizedKeys or [ ]);
        shell = usersExternal.${name}.shell or users.${name}.shell or "bash";
        hashedPassword = usersExternal.${name}.hashedPassword or users.${name}.hashedPassword or null;
        trustedNixKeys = usersExternal.${name}.trustedNixKeys or users.${name}.trustedNixKeys or [ ];
        home = { ... }: {
          imports = [ usersExternal.${name}.home or { } ] ++ [ users.${name}.home or { } ];
        };
        os = { ... }@inputs:
          let
            modules = [ ((users.${name}.os or ({ ... }: { })) inputs) ] ++ [ ((usersExternal.${name}.os or ({ ... }: { })) inputs) ];
          in
          foldl recursiveUpdate { } modules;
        uid = usersExternal.${name}.uid or users.${name}.uid;
      })
      allUserNames);
in
{
  flake = {
    users = if (pathExists ../external/private/users) then allUsers else users;
  };
}
