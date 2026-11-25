from pricing import load_catalog


def test_catalog_is_priced_in_pounds():
    assert load_catalog().currency == "GBP"
