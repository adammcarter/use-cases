import configparser
import json
from pathlib import Path


def load_fixture():
    return json.loads(Path("fixtures/users.json").read_text())


def load_config():
    config = configparser.ConfigParser()
    config.read("config/auth.ini")
    return config


def test_legacy_login_contract():
    users = load_fixture()
    config = load_config()

    assert users["valid"]["username"] == "legacy-user"
    assert users["valid"]["password"] == "secret"
    assert config["auth"]["audit_enabled"] == "true"

    # In a real legacy repo this script might spawn binaries, call HTTP,
    # or bridge several existing systems.
    print("PASS")
