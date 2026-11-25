package shortener

import (
	"errors"
	"net/url"
	"time"
)

var (
	ErrInvalidURL = errors.New("invalid url")
	ErrNotFound   = errors.New("not found")
	ErrExpired    = errors.New("link expired")
)

type Link struct {
	Code    string
	Target  string
	Expires time.Time
}

type Store interface {
	Get(code string) (Link, bool)
	Put(link Link)
}

type Shortener struct {
	store Store
	codes func() string
	now   func() time.Time
}

func New(store Store, codes func() string, now func() time.Time) *Shortener {
	return &Shortener{store: store, codes: codes, now: now}
}

func (s *Shortener) Shorten(target string, ttl time.Duration) (string, error) {
	u, err := url.Parse(target)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return "", ErrInvalidURL
	}
	code := s.codes()
	for {
		if _, taken := s.store.Get(code); !taken {
			break
		}
		code = s.codes()
	}
	link := Link{Code: code, Target: target}
	if ttl > 0 {
		link.Expires = s.now().Add(ttl)
	}
	s.store.Put(link)
	return code, nil
}

func (s *Shortener) Resolve(code string) (string, error) {
	link, ok := s.store.Get(code)
	if !ok {
		return "", ErrNotFound
	}
	if !link.Expires.IsZero() && s.now().After(link.Expires) {
		return "", ErrExpired
	}
	return link.Target, nil
}

type MemoryStore map[string]Link

func (m MemoryStore) Get(code string) (Link, bool) { l, ok := m[code]; return l, ok }
func (m MemoryStore) Put(link Link)                { m[link.Code] = link }
