#include "ringbuf.h"

bool ringbuf_init(ringbuf *rb, int *storage, size_t capacity, bool overwrite) {
    if (!rb || !storage || capacity == 0) {
        return false;
    }
    rb->data = storage;
    rb->capacity = capacity;
    rb->head = 0;
    rb->count = 0;
    rb->overwrite = overwrite;
    return true;
}

bool ringbuf_push(ringbuf *rb, int value) {
    if (rb->count == rb->capacity) {
        if (!rb->overwrite) {
            return false;
        }
        rb->head = (rb->head + 1) % rb->capacity;
        rb->count--;
    }
    size_t tail = (rb->head + rb->count) % rb->capacity;
    rb->data[tail] = value;
    rb->count++;
    return true;
}

bool ringbuf_pop(ringbuf *rb, int *out) {
    if (rb->count == 0) {
        return false;
    }
    *out = rb->data[rb->head];
    rb->head = (rb->head + 1) % rb->capacity;
    rb->count--;
    return true;
}

bool ringbuf_peek(const ringbuf *rb, int *out) {
    if (rb->count == 0) {
        return false;
    }
    *out = rb->data[rb->head];
    return true;
}

size_t ringbuf_count(const ringbuf *rb) {
    return rb->count;
}

bool ringbuf_is_full(const ringbuf *rb) {
    return rb->count == rb->capacity;
}
