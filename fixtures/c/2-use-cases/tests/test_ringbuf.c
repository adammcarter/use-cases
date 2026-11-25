#include <stdio.h>
#include <string.h>

#include "ringbuf.h"

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); \
            return 1;                                                      \
        }                                                                  \
    } while (0)

static int starts_empty(void) {
    int storage[4];
    ringbuf rb;
    CHECK(ringbuf_init(&rb, storage, 4, false));
    CHECK(ringbuf_count(&rb) == 0);
    int value;
    CHECK(!ringbuf_pop(&rb, &value));
    return 0;
}

/* @use-case:ringbuf.buffer.fifo#unit-tests.push-then-pop */
static int push_then_pop(void) {
    int storage[4];
    ringbuf rb;
    ringbuf_init(&rb, storage, 4, false);
    CHECK(ringbuf_push(&rb, 7));
    CHECK(ringbuf_push(&rb, 8));
    int value;
    CHECK(ringbuf_pop(&rb, &value) && value == 7);
    CHECK(ringbuf_pop(&rb, &value) && value == 8);
/* @use-case:end ringbuf.buffer.fifo#unit-tests.push-then-pop */
    return 0;
}

/* @use-case:ringbuf.buffer.fifo#unit-tests.wrap-around */
static int wraps_around(void) {
    int storage[3];
    ringbuf rb;
    ringbuf_init(&rb, storage, 3, false);
    int value;
    for (int i = 0; i < 10; i++) {
        CHECK(ringbuf_push(&rb, i));
        CHECK(ringbuf_pop(&rb, &value) && value == i);
/* @use-case:end ringbuf.buffer.fifo#unit-tests.wrap-around */
    }
    return 0;
}

/* @use-case:ringbuf.buffer.full#unit-tests.refuses */
static int rejects_push_when_full(void) {
    int storage[2];
    ringbuf rb;
    ringbuf_init(&rb, storage, 2, false);
    CHECK(ringbuf_push(&rb, 1));
    CHECK(ringbuf_push(&rb, 2));
    CHECK(ringbuf_is_full(&rb));
    CHECK(!ringbuf_push(&rb, 3));
/* @use-case:end ringbuf.buffer.full#unit-tests.refuses */
    return 0;
}

/* @use-case:ringbuf.buffer.full#unit-tests.overwrites-oldest */
static int overwrite_mode_drops_oldest(void) {
    int storage[2];
    ringbuf rb;
    ringbuf_init(&rb, storage, 2, true);
    ringbuf_push(&rb, 1);
    ringbuf_push(&rb, 2);
    CHECK(ringbuf_push(&rb, 3));
    int value;
    CHECK(ringbuf_pop(&rb, &value) && value == 2);
    CHECK(ringbuf_pop(&rb, &value) && value == 3);
/* @use-case:end ringbuf.buffer.full#unit-tests.overwrites-oldest */
    return 0;
}

/* @use-case:ringbuf.buffer.fifo#unit-tests.peek */
static int peek_does_not_remove(void) {
    int storage[2];
    ringbuf rb;
    ringbuf_init(&rb, storage, 2, false);
    ringbuf_push(&rb, 42);
    int value;
    CHECK(ringbuf_peek(&rb, &value) && value == 42);
    CHECK(ringbuf_count(&rb) == 1);
/* @use-case:end ringbuf.buffer.fifo#unit-tests.peek */
    return 0;
}

static const struct {
    const char *name;
    int (*run)(void);
} tests[] = {
    {"starts_empty", starts_empty},
    {"push_then_pop", push_then_pop},
    {"wraps_around", wraps_around},
    {"rejects_push_when_full", rejects_push_when_full},
    {"overwrite_mode_drops_oldest", overwrite_mode_drops_oldest},
    {"peek_does_not_remove", peek_does_not_remove},
};

int main(int argc, char **argv) {
    size_t count = sizeof tests / sizeof tests[0];
    for (size_t i = 0; i < count; i++) {
        if (argc < 2 || strcmp(argv[1], tests[i].name) == 0) {
            if (tests[i].run() != 0) {
                return 1;
            }
            if (argc >= 2) {
                return 0;
            }
        }
    }
    if (argc >= 2) {
        fprintf(stderr, "unknown test: %s\n", argv[1]);
        return 2;
    }
    return 0;
}
