/* Synthetic metadata only; no game files or real keysets. */
#include "../Vendor/hacPack/nacp.c"
#include <stdint.h>
static unsigned checks;
static void expect(int ok, const char *message) {
    if (!ok) { fprintf(stderr,"FAIL: %s\n",message);exit(1); }
    printf("PASS: %s\n",message);checks++;
}
static unsigned char raw[NACP_SIZE], entries[NACP_LANGUAGE_SIZE * (NACP_MAX_LANGUAGES + 1)];
static void fixture(size_t languages) {
    memset(raw,0,sizeof(raw));memset(entries,0,sizeof(entries));
    for(size_t i=0;i<languages;i++) {
        memcpy(entries+i*NACP_LANGUAGE_SIZE,"Example Game",12);
        memcpy(entries+i*NACP_LANGUAGE_SIZE+0x200,"Publisher",9);
    }
    memcpy(raw+0x3060,"1.2.1",5);raw[NACP_TITLE_FORMAT_OFFSET]=1;
}
static void compress_entries(size_t bytes) {
    memset(raw,0,0x3000);
    z_stream stream={0};
    if(deflateInit2(&stream,6,Z_DEFLATED,-MAX_WBITS,8,Z_DEFAULT_STRATEGY)!=Z_OK)exit(1);
    stream.next_in=entries;stream.avail_in=(uInt)bytes;
    stream.next_out=raw+2;stream.avail_out=0x2FFE;
    if(deflate(&stream,Z_FINISH)!=Z_STREAM_END)exit(1);
    raw[0]=(unsigned char)stream.total_out;raw[1]=(unsigned char)(stream.total_out>>8);
    deflateEnd(&stream);
}
int main(void) {
    fixture(16);raw[NACP_TITLE_FORMAT_OFFSET]=0;memcpy(raw,entries,0x3000);
    expect(nacp_validate(raw,sizeof(raw))==NULL,"legacy uncompressed title information accepted");
    fixture(18);compress_entries(18*NACP_LANGUAGE_SIZE);
    unsigned char before[NACP_SIZE];memcpy(before,raw,sizeof(raw));
    expect(nacp_validate(raw,sizeof(raw))==NULL,"18 compressed language entries accepted");
    expect(memcmp(before,raw,sizeof(raw))==0,"validation leaves original compressed metadata and settings unchanged");
    fixture(32);compress_entries(32*NACP_LANGUAGE_SIZE);
    expect(nacp_validate(raw,sizeof(raw))==NULL,"32 compressed language slots used by newer updates accepted");
    expect(nacp_validate(raw,sizeof(raw)-1)!=NULL,"truncated control information rejected");
    raw[0]=0;raw[1]=0;expect(nacp_validate(raw,sizeof(raw))!=NULL,"empty compressed stream rejected");
    raw[0]=0xff;raw[1]=0xff;expect(nacp_validate(raw,sizeof(raw))!=NULL,"compressed payload outside title region rejected");
    fixture(32);compress_entries(32*NACP_LANGUAGE_SIZE);raw[2]=7;
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"invalid deflate stream rejected");
    fixture(32);compress_entries(32*NACP_LANGUAGE_SIZE);raw[0]--;
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"truncated compressed stream rejected");
    fixture(32);compress_entries(32*NACP_LANGUAGE_SIZE);raw[0]++;
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"unexpected data after compressed stream rejected");
    fixture(33);compress_entries(33*NACP_LANGUAGE_SIZE);
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"expansion beyond fixed language limit rejected");
    fixture(16);compress_entries(16*NACP_LANGUAGE_SIZE-1);
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"partial language entry rejected");
    fixture(0);compress_entries(NACP_LANGUAGE_SIZE);
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"compressed metadata without a game title rejected");
    fixture(16);compress_entries(16*NACP_LANGUAGE_SIZE);raw[NACP_TITLE_FORMAT_OFFSET]=2;
    expect(nacp_validate(raw,sizeof(raw))!=NULL,"unknown title encoding rejected");
    printf("%u NACP checks passed.\n",checks);return 0;
}
