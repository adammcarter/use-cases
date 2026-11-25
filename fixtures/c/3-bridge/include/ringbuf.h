#ifndef RINGBUF_H
#define RINGBUF_H

#include <stdbool.h>
#include <stddef.h>

typedef struct {
    int *data;
    size_t capacity;
    size_t head;
    size_t count;
    bool overwrite;
} ringbuf;

bool ringbuf_init(ringbuf *rb, int *storage, size_t capacity, bool overwrite);
bool ringbuf_push(ringbuf *rb, int value);
bool ringbuf_pop(ringbuf *rb, int *out);
bool ringbuf_peek(const ringbuf *rb, int *out);
size_t ringbuf_count(const ringbuf *rb);
bool ringbuf_is_full(const ringbuf *rb);

#endif
