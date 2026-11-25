package shortener

import (
	"errors"
	"testing"
	"time"
)

func sequence(codes ...string) func() string {
	i := 0
	return func() string { c := codes[i]; i++; return c }
}

var start = time.Date(2026, 9, 25, 12, 0, 0, 0, time.UTC)

// @use-case:linkshort.links.shorten#unit-tests.round-trip
func TestShortenAndResolve(t *testing.T) {
	s := New(MemoryStore{}, sequence("abc"), func() time.Time { return start })
	code, err := s.Shorten("https://example.com/docs", 0)
	if err != nil || code != "abc" {
		t.Fatalf("got %q, %v", code, err)
	}
	target, err := s.Resolve("abc")
	if err != nil || target != "https://example.com/docs" {
		t.Fatalf("got %q, %v", target, err)
	}
}
// @use-case:end linkshort.links.shorten#unit-tests.round-trip

// @use-case:linkshort.links.shorten#unit-tests.invalid-refused
func TestRejectsInvalidURLs(t *testing.T) {
	cases := map[string]string{
		"no scheme":  "example.com",
		"ftp scheme": "ftp://example.com",
		"no host":    "https://",
	}
	for name, input := range cases {
		t.Run(name, func(t *testing.T) {
			s := New(MemoryStore{}, sequence("x"), time.Now)
			if _, err := s.Shorten(input, 0); !errors.Is(err, ErrInvalidURL) {
				t.Errorf("Shorten(%q) error = %v", input, err)
			}
		})
	}
}
// @use-case:end linkshort.links.shorten#unit-tests.invalid-refused

// @use-case:linkshort.links.shorten#unit-tests.collision-retry
func TestRetriesOnCollision(t *testing.T) {
	store := MemoryStore{"taken": {Code: "taken", Target: "https://a.example"}}
	s := New(store, sequence("taken", "fresh"), time.Now)
	code, _ := s.Shorten("https://b.example", 0)
	if code != "fresh" {
		t.Fatalf("code = %q", code)
	}
}
// @use-case:end linkshort.links.shorten#unit-tests.collision-retry

// @use-case:linkshort.links.expiry#unit-tests.expired
func TestExpiredLinksDoNotResolve(t *testing.T) {
	now := start
	s := New(MemoryStore{}, sequence("tmp"), func() time.Time { return now })
	s.Shorten("https://example.com", time.Hour)
	now = start.Add(2 * time.Hour)
	if _, err := s.Resolve("tmp"); !errors.Is(err, ErrExpired) {
		t.Fatalf("err = %v", err)
	}
}
// @use-case:end linkshort.links.expiry#unit-tests.expired

func TestCustomAliases(t *testing.T) {
	t.Skip("custom aliases land in v2")
}
