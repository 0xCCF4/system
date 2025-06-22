{ ... }: {


  config = {
    noxa.secrets.options.masterIdentities = [
      {
        identity = "/home/mx/Documents/nixos-new/external/private/secrets/master-identity.age";
        pubkey = "age139u6cdr527jm5x4e3fffqpd76gewwydlz2ekgr78n6yffeh3ce3q0mk2ma";
      }
    ];
    noxa.secrets.secretsPath = ./external/private/secrets;

    system.stateVersion = "25.11";
  };

}
