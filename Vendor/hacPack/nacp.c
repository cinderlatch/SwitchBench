/* SwitchBench local modifications, 2026-11-03 through 2026-11-04. See ../CHANGES.md; upstream authors and licenses retained. */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>
#include "nacp.h"
#include "filepath.h"

#define NACP_SIZE 0x4000
#define NACP_LANGUAGE_SIZE 0x300
#define NACP_TITLE_FORMAT_OFFSET 0x3215
#define NACP_MAX_LANGUAGES 32

/* Validate a decoded view only. The original NACP, including compressed title
 * data and all newer settings, is packaged without modification. */
static const char *nacp_validate(const unsigned char *raw, size_t size)
{
    if (size < NACP_SIZE) return "Error: Incomplete control.nacp";
    const unsigned char *entries = raw;
    unsigned char expanded[NACP_LANGUAGE_SIZE * NACP_MAX_LANGUAGES];
    size_t count = 16;
    switch (raw[NACP_TITLE_FORMAT_OFFSET]) {
        case 0: break;
        case 1: {
            size_t compressed_size = raw[0] | ((size_t)raw[1] << 8);
            if (compressed_size == 0 || compressed_size > 0x2FFE)
                return "Error: Invalid compressed title data size in control.nacp";
            z_stream stream = {0};
            stream.next_in = (Bytef *)(raw + 2);
            stream.avail_in = (uInt)compressed_size;
            stream.next_out = expanded;
            stream.avail_out = sizeof(expanded);
            if (inflateInit2(&stream, -MAX_WBITS) != Z_OK)
                return "Error: Could not initialize title data reader";
            int result = inflate(&stream, Z_FINISH);
            size_t bytes = stream.total_out;
            int valid = result == Z_STREAM_END && stream.avail_in == 0 &&
                        bytes > 0 && bytes % NACP_LANGUAGE_SIZE == 0;
            inflateEnd(&stream);
            if (!valid) return "Error: Invalid or oversized compressed title data in control.nacp";
            entries = expanded; count = bytes / NACP_LANGUAGE_SIZE;
            break;
        }
        default: return "Error: Unsupported title data format in control.nacp";
    }
    int has_title = 0;
    for (size_t i = 0; i < count; ++i) {
        const unsigned char *title = entries + i * NACP_LANGUAGE_SIZE;
        const unsigned char *author = title + 0x200;
        if (!memchr(title, 0, 0x200) || !memchr(author, 0, 0x100))
            return "Error: Unterminated title or author in control.nacp";
        if (title[0]) {
            has_title = 1;
            if (author[0]) return NULL;
        }
    }
    return has_title ? "Error: Invalid Author in control.nacp" : "Error: Invalid Title Name in control.nacp";
}

void nacp_process(hp_settings_t *settings)
{
    filepath_t path;
    filepath_init(&path);
    filepath_copy(&path, &settings->romfs_dir);
    filepath_append(&path, "control.nacp");
    FILE *file = os_fopen(path.os_path, OS_MODE_READ);
    if (!file) { fprintf(stderr, "Failed to open control.nacp!\n"); exit(EXIT_FAILURE); }
    unsigned char raw[NACP_SIZE];
    size_t size = fread(raw, 1, sizeof(raw), file);
    fclose(file);
    printf("Validating game title information\n");
    const char *error = nacp_validate(raw, size);
    if (error) { fprintf(stderr, "%s\n", error); exit(EXIT_FAILURE); }
}
