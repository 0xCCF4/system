from datetime import datetime, timezone

import pytest

from pki.certinfo import days_until_expiry, parse_not_after

SAMPLE = {"not_after": "2027-01-02T03:04:05Z"}


def test_parse_not_after():
    parsed = parse_not_after(SAMPLE)
    assert parsed == datetime(2027, 1, 2, 3, 4, 5, tzinfo=timezone.utc)


def test_parse_not_after_missing_field():
    with pytest.raises(ValueError):
        parse_not_after({})


def test_days_until_expiry_future():
    now = datetime(2027, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
    assert days_until_expiry(SAMPLE, now=now) == 1


def test_days_until_expiry_past_is_negative():
    now = datetime(2027, 2, 1, 0, 0, 0, tzinfo=timezone.utc)
    assert days_until_expiry(SAMPLE, now=now) < 0
