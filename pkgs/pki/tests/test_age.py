import pytest

from pki.age import encrypt


def test_encrypt_rejects_empty_recipients():
    # No real `age` binary needed -- this validation must short-circuit
    # before ever shelling out, since `age` with no `-r` at all doesn't
    # fail the way you'd want (it can fall back to reading recipients
    # from stdin), which would risk silently "encrypting" to nobody.
    with pytest.raises(ValueError):
        encrypt(recipients=[], plaintext="root key material")
