#ifndef SWITCHBENCH_WINDOWS_NATIVE_H
#define SWITCHBENCH_WINDOWS_NATIVE_H

#include <stddef.h>
#include <stdint.h>

void *sp_zstd_create(void);
void sp_zstd_free(void *ctx);
size_t sp_zstd_decode(void *ctx, const void *src, size_t length, size_t *consumed,
                      void *dst, size_t capacity, size_t *produced);
size_t sp_zstd_encode(const void *src, size_t length, void *dst, size_t capacity, int32_t level);
void *sp_sha_create(void);
void sp_sha_update(void *ctx, const void *bytes, size_t size);
void sp_sha_digest(void *ctx, void *out);
void sp_sha_free(void *ctx);
int32_t sp_aes_ctr(const void *key, const void *counter, const void *src, void *dst, size_t size);
size_t sp_inflate_raw(const void *src, size_t size, void *dst, size_t capacity);
uint32_t sp_publish(const uint16_t *src, const uint16_t *dst);

#endif
