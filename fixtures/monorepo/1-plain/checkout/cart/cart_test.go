package cart

import (
	"errors"
	"testing"
)

func load(t *testing.T) Catalog {
	t.Helper()
	c, err := LoadCatalog("../../catalog/prices.json")
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func TestBulkTiers(t *testing.T) {
	c := load(t)
	cases := []struct {
		quantity int
		pence    int
	}{{4, 5000}, {5, 5625}, {12, 12750}}
	for _, tc := range cases {
		got, _ := c.LineTotal(Line{"coffee-beans", tc.quantity})
		if got != tc.pence {
			t.Errorf("%d bags = %d pence, want %d", tc.quantity, got, tc.pence)
		}
	}
}

func TestTotalAcrossLines(t *testing.T) {
	c := load(t)
	got, _ := c.Total([]Line{{"grinder", 1}, {"filter-papers", 20}})
	if got != 8900+4800 {
		t.Fatalf("total = %d", got)
	}
}

func TestEmptyCartIsFree(t *testing.T) {
	got, err := load(t).Total(nil)
	if err != nil || got != 0 {
		t.Fatalf("got %d, %v", got, err)
	}
}

func TestUnknownItem(t *testing.T) {
	if _, err := load(t).Total([]Line{{"teapot", 1}}); !errors.Is(err, ErrUnknownItem) {
		t.Fatalf("err = %v", err)
	}
}
