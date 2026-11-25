package cart

import (
	"encoding/json"
	"errors"
	"math"
	"os"
	"strconv"
)

type tier struct {
	Min     int `json:"min"`
	Percent int `json:"percent"`
}

type item struct {
	UnitPrice string `json:"unit_price"`
	Bulk      []tier `json:"bulk"`
}

type Catalog struct {
	Currency string          `json:"currency"`
	Items    map[string]item `json:"items"`
}

var ErrUnknownItem = errors.New("unknown item")

func LoadCatalog(path string) (Catalog, error) {
	var c Catalog
	data, err := os.ReadFile(path)
	if err != nil {
		return c, err
	}
	return c, json.Unmarshal(data, &c)
}

type Line struct {
	SKU      string
	Quantity int
}

// LineTotal is the price of one cart line in pence, after the best bulk tier.
func (c Catalog) LineTotal(line Line) (int, error) {
	it, ok := c.Items[line.SKU]
	if !ok {
		return 0, ErrUnknownItem
	}
	price, err := strconv.ParseFloat(it.UnitPrice, 64)
	if err != nil {
		return 0, err
	}
	// @use-case:shop.rules.bulk-discount#checkout-tiers
	percent := 0
	for _, t := range it.Bulk {
		if line.Quantity >= t.Min && t.Percent > percent {
			percent = t.Percent
		}
	}
	// @use-case:end shop.rules.bulk-discount#checkout-tiers
	gross := math.Round(price * 100 * float64(line.Quantity))
	return int(math.Round(gross * float64(100-percent) / 100)), nil
}

// Total adds every line. An empty cart totals zero.
// @use-case:shop.checkout.cart.total#sum-lines
func (c Catalog) Total(lines []Line) (int, error) {
	total := 0
	for _, line := range lines {
		pence, err := c.LineTotal(line)
		if err != nil {
			return 0, err
		}
		total += pence
	}
	return total, nil
// @use-case:end shop.checkout.cart.total#sum-lines
}
