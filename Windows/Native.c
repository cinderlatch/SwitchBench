/* Windows bridge to the bundled cryptographic library and zlib. */
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <windows.h>
#include <mbedtls/aes.h>
#include <mbedtls/sha256.h>
#include <zlib.h>

void *sp_sha_create(void) {
    mbedtls_sha256_context *ctx = malloc(sizeof(*ctx));
    if (ctx) {
        mbedtls_sha256_init(ctx);
        mbedtls_sha256_starts(ctx, 0);
    }
    return ctx;
}
void sp_sha_update(void *ctx, const unsigned char *bytes, size_t size) {
    mbedtls_sha256_update(ctx, bytes, size);
}
void sp_sha_digest(void *ctx, unsigned char *out) {
    mbedtls_sha256_context copy;
    mbedtls_sha256_init(&copy);
    mbedtls_sha256_clone(&copy, ctx);
    mbedtls_sha256_finish(&copy, out);
    mbedtls_sha256_free(&copy);
}
void sp_sha_free(void *ctx) {
    mbedtls_sha256_free(ctx);
    free(ctx);
}
int sp_aes_ctr(const unsigned char *key, const unsigned char *counter,
               const unsigned char *src, unsigned char *dst, size_t size) {
    mbedtls_aes_context ctx;
    unsigned char nonce[16], stream[16] = {0};
    size_t offset = 0;
    memcpy(nonce, counter, sizeof(nonce));
    mbedtls_aes_init(&ctx);
    int result = mbedtls_aes_setkey_enc(&ctx, key, 128);
    if (result == 0) result = mbedtls_aes_crypt_ctr(&ctx, size, &offset, nonce, stream, src, dst);
    mbedtls_aes_free(&ctx);
    return result;
}
size_t sp_inflate_raw(const unsigned char *src, size_t size, unsigned char *dst, size_t capacity) {
    z_stream stream = {0};
    if (size > UINT_MAX || capacity > UINT_MAX || inflateInit2(&stream, -MAX_WBITS) != Z_OK) return 0;
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)size;
    stream.next_out = dst;
    stream.avail_out = (uInt)capacity;
    int result = inflate(&stream, Z_FINISH);
    size_t written = result == Z_STREAM_END && stream.avail_in == 0 ? stream.total_out : 0;
    inflateEnd(&stream);
    return written;
}
/* MoveFileW refuses existing destinations and never copies across volumes. */
unsigned long sp_publish(const wchar_t *src, const wchar_t *dst) {
    return MoveFileExW(src, dst, 0) ? 0 : GetLastError();
}
