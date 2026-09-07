import pytest

from pki.csr import OrgNames, build_csr_request


def test_build_csr_request_defaults():
    req = build_csr_request(cn="lux.server")
    assert req["CN"] == "lux.server"
    assert req["hosts"] == []
    assert req["key"] == {"algo": "ecdsa", "size": 256}
    assert req["names"] == [{"C": "", "ST": "", "L": "", "O": ""}]


def test_build_csr_request_with_sans_and_org():
    org = OrgNames(country="DE", state="Hessen", locality="Darmstadt", organization="Example")
    req = build_csr_request(cn="svc.lux", sans=["svc.lux", "10.0.0.1"], org=org, key_algo="rsa", key_size=2048)
    assert req["hosts"] == ["svc.lux", "10.0.0.1"]
    assert req["key"] == {"algo": "rsa", "size": 2048}
    assert req["names"] == [{"C": "DE", "ST": "Hessen", "L": "Darmstadt", "O": "Example"}]


def test_build_csr_request_empty_cn_rejected():
    with pytest.raises(ValueError):
        build_csr_request(cn="")


def test_build_csr_request_sans_default_is_not_shared_mutable_list():
    req1 = build_csr_request(cn="a")
    req1["hosts"].append("mutated")
    req2 = build_csr_request(cn="b")
    assert req2["hosts"] == []
