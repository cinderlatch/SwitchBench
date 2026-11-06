#include "../Vendor/zstd-1.5.7/lib/zstd.h"
#include <stdint.h>
void *sp_zstd_create(void) {
    ZSTD_DCtx *ctx = ZSTD_createDCtx();
    if (ctx && ZSTD_isError(ZSTD_DCtx_setParameter(ctx, ZSTD_d_windowLogMax, 27))) { ZSTD_freeDCtx(ctx); return 0; }
    return ctx;
}
void sp_zstd_free(void *ctx) { ZSTD_freeDCtx(ctx); }
size_t sp_zstd_decode(void *ctx, const void *src, size_t length, size_t *consumed,
                      void *dst, size_t capacity, size_t *produced) {
    ZSTD_inBuffer input = { src, length, 0 };
    ZSTD_outBuffer output = { dst, capacity, 0 };
    size_t result = ZSTD_decompressStream(ctx, &output, &input);
    *consumed = input.pos; *produced = output.pos;
    return ZSTD_isError(result) ? SIZE_MAX : result;
}
/* Encode an independent Zstandard block. */
size_t sp_zstd_encode(const void *src, size_t length, void *dst, size_t capacity, int level) {
    size_t result = ZSTD_compress(dst, capacity, src, length, level);
    return ZSTD_isError(result) ? SIZE_MAX : result;
}
