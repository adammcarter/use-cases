.PHONY: test test-pricing test-checkout test-storefront

test: test-pricing test-checkout test-storefront

test-pricing:
	cd pricing && python3 -m pytest -q

test-checkout:
	cd checkout && go test ./...

test-storefront:
	cd storefront && node --test
