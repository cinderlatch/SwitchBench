/* Synthetic fixtures only; no production keys or game data. */
#include "../Vendor/hactool/nca.c"
#include <stddef.h>

_Static_assert(sizeof(nca_fs_header_t) == 0x200, "FS header ABI");
_Static_assert(offsetof(nca_fs_header_t, meta_hash_info) == 0x1a0, "metadata offset");
_Static_assert(sizeof(nca_meta_hash_data_t) == 0xe8, "metadata descriptor ABI");

static unsigned checks;
static void expect(int ok, const char *name) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", name); exit(1); }
    printf("PASS: %s\n", name); checks++;
}

enum { SECTION_SIZE = 0x18200, TABLE_START = 0x4000,
       HASH_START = 0x14000, DESCRIPTOR = 0x18000 };
static unsigned char bytes[SECTION_SIZE];
static nca_fs_header_t header;

static void seal_descriptor(void) {
    sha256_hash_buffer(header.meta_hash_info.hash, bytes + DESCRIPTOR, sizeof(nca_meta_hash_data_t));
}

static void fixture(void) {
    memset(bytes, 0, sizeof(bytes)); memset(&header, 0, sizeof(header));
    header.meta_hash_type = 1;
    header.bktr_superblock.relocation_header = (bktr_header_t){ .offset = TABLE_START, .size = 0x8000 };
    header.bktr_superblock.subsection_header = (bktr_header_t){ .offset = 0xc000, .size = 0x8000 };
    header.meta_hash_info.offset = DESCRIPTOR;
    header.meta_hash_info.size = sizeof(nca_meta_hash_data_t);
    for (unsigned i = TABLE_START; i < HASH_START; ++i) bytes[i] = (unsigned char)(i * 17 + i / 251);
    for (unsigned i = 0; i < 4; ++i)
        sha256_hash_buffer(bytes + HASH_START + i * 32, bytes + TABLE_START + i * 0x4000, 0x4000);
    nca_meta_hash_data_t meta = {0};
    meta.layer_info_offset = HASH_START;
    meta.ivfc.magic = MAGIC_IVFC; meta.ivfc.num_levels = 3; meta.ivfc.master_hash_size = 32;
    meta.ivfc.level_headers[0] = (ivfc_level_hdr_t){ .hash_data_size = 0x4000, .block_size = 14 };
    meta.ivfc.level_headers[1] = (ivfc_level_hdr_t){ .logical_offset = 0x4000, .hash_data_size = 0x10000, .block_size = 14 };
    sha256_hash_buffer(meta.ivfc.master_hash, bytes + HASH_START, 0x4000);
    memcpy(bytes + DESCRIPTOR, &meta, sizeof(meta)); seal_descriptor();
}

static int accepted(int encrypted) {
    nca_section_ctx_t ctx = {0};
    ctx.header = &header; ctx.bktr_ctx.superblock = &header.bktr_superblock;
    ctx.size = sizeof(bytes); ctx.file = tmpfile();
    if (!ctx.file) exit(1);
    unsigned char *body = malloc(sizeof(bytes)); memcpy(body, bytes, sizeof(bytes));
    if (encrypted) {
        unsigned char key[16] = {7};
        ctx.type = BKTR; ctx.crypt_type = CRYPT_BKTR;
        ctx.aes = new_aes_ctx(key, sizeof(key), AES_MODE_CTR);
        aes_setiv(ctx.aes, ctx.ctr, sizeof(ctx.ctr));
        aes_encrypt(ctx.aes, body, body, sizeof(bytes));
    } else { ctx.is_decrypted = 1; ctx.type = ROMFS; }
    fwrite(body, 1, sizeof(bytes), ctx.file); free(body);
    const char *error = nca_validate_bktr_layout(&ctx);
    if (ctx.aes) free_aes_ctx(ctx.aes);
    fclose(ctx.file); return error == NULL;
}

int main(void) {
    fixture(); expect(accepted(0), "new metadata layout accepted with verified tables");
    expect(accepted(1), "encrypted patch metadata verified before enabling virtual reads");
    bytes[TABLE_START + 7] ^= 1; expect(!accepted(1), "corrupt relocation table rejected");
    fixture(); bytes[0xc000 + 11] ^= 1; expect(!accepted(1), "corrupt counter table rejected");
    fixture(); bytes[HASH_START] ^= 1; expect(!accepted(1), "corrupt metadata hash tree rejected");
    fixture(); bytes[DESCRIPTOR + 4] ^= 1; expect(!accepted(1), "corrupt descriptor rejected");
    fixture(); header.meta_hash_info.hash[0] ^= 1; expect(!accepted(1), "wrong descriptor digest rejected");
    fixture(); header.meta_hash_type = 2; expect(!accepted(0), "unknown metadata type rejected");
    fixture(); header.meta_hash_info.offset = UINT64_MAX - 1; expect(!accepted(0), "overflowing descriptor extent rejected");
    fixture(); header.meta_hash_info.size--; expect(!accepted(0), "truncated descriptor rejected");
    fixture(); header.bktr_superblock.relocation_header.size = UINT64_MAX; expect(!accepted(0), "overflowing table extent rejected");
    fixture(); header.bktr_superblock.subsection_header.offset--; expect(!accepted(0), "overlapping patch tables rejected");
    fixture(); ((nca_meta_hash_data_t*)(bytes + DESCRIPTOR))->ivfc.num_levels = 99; seal_descriptor();
    expect(!accepted(0), "invalid integrity layer count rejected");
    fixture(); ((nca_meta_hash_data_t*)(bytes + DESCRIPTOR))->ivfc.level_headers[0].block_size = 31; seal_descriptor();
    expect(!accepted(0), "excessive hash-block allocation rejected");
    fixture(); ((nca_meta_hash_data_t*)(bytes + DESCRIPTOR))->ivfc.level_headers[1].hash_data_size--; seal_descriptor();
    expect(!accepted(0), "partial authentication of patch tables rejected");
    fixture(); ((nca_meta_hash_data_t*)(bytes + DESCRIPTOR))->ivfc.level_headers[0].logical_offset = UINT64_MAX; seal_descriptor();
    expect(!accepted(0), "overflowing hash-layer extent rejected");
    fixture(); header.meta_hash_type = 0; expect(!accepted(0), "unverified trailing metadata rejected");
    /* Legacy tables end at the section boundary. */
    header.bktr_superblock.subsection_header.size = SECTION_SIZE - 0xc000;
    expect(accepted(0), "legacy contiguous layout remains supported");
    header.bktr_superblock.relocation_header.size--;
    expect(!accepted(0), "legacy table gap remains rejected");
    printf("%u BKTR checks passed.\n", checks); return 0;
}
