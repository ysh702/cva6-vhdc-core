// =============================================================================
// bench.c — HDEC Micro-benchmark
// Compile: -DMODE=N   where N=0(SW_HDC) 1(SW_ECC) 2(HW_HDC) 3(HW_ECC) 4(HW_FUSED)
// Output: tohost=(code<<1), code=(cyc&0xFFFF)|((ir&0xFFFF)<<16)
// =============================================================================
#include <stdint.h>

static inline uint64_t rdcycle(void)  { uint64_t c; asm("rdcycle %0":"=r"(c)); return c; }
static inline uint64_t rdinstret(void){ uint64_t i; asm("rdinstret %0":"=r"(i)); return i; }

extern volatile uint64_t tohost;
static void __attribute__((noreturn)) finish(uint64_t code) {
    tohost = ((code << 1) | 1) & 0xFFFFFFFFULL;
    asm volatile("nop");
    while(1) asm volatile("");
}

// =============================================================================
// Shared Data: 1024-bit = 16×uint64_t, 16 features, 4 prototypes, ECC 256-bit
// =============================================================================
#define HV_W 16
#define N_FEAT 4
#define N_PROTO 4
#define ECC_W 4

static const uint64_t F[N_FEAT][HV_W] = {
 {0xAAAAAAAABBBBBBBB,0xCCCCCCCCDDDDDDDD,0xEEEEEEEEFFFFFFFF,0x1111111122222222,
  0x3333333344444444,0x5555555566666666,0x7777777788888888,0x9999999900000000,
  0xAAAAAAAA11111111,0xBBBBBBBB22222222,0xCCCCCCCC33333333,0xDDDDDDDD44444444,
  0xEEEEEEEE55555555,0xFFFFFFFF66666666,0x0000000077777777,0x1111111188888888},
 {0x1111111122222222,0x3333333344444444,0x5555555566666666,0x7777777788888888,
  0x99999999AAAAAAAA,0xBBBBBBBBCCCCCCCC,0xDDDDDDDDEEEEEEEE,0xFFFFFFFFFF000000,
  0x0000000011111111,0x2222222233333333,0x4444444455555555,0x6666666677777777,
  0x8888888899999999,0xAAAAAAAABBBBBBBB,0xCCCCCCCCDDDDDDDD,0xEEEEEEEEFFFFFFFF},
 {0xDEADBEEFCAFEBABE,0x1234567890ABCDEF,0xFEDCBA9876543210,0x0F1E2D3C4B5A6978,
  0x0011223344556677,0x8899AABBCCDDEEFF,0xFFEEDDCCBBAA9988,0x7766554433221100,
  0x0123456789ABCDEF,0xFEDCBA9876543210,0xDEADBEEFCAFEBABE,0x0F1E2D3C4B5A6978,
  0x8899AABBCCDDEEFF,0x0011223344556677,0xFFEEDDCCBBAA9988,0x7766554433221100},
 {0x0123456789ABCDEF,0x0011223344556677,0x8899AABBCCDDEEFF,0xFFEEDDCCBBAA9988,
  0x7766554433221100,0x0F1E2D3C4B5A6978,0xDEADBEEFCAFEBABE,0xFEDCBA9876543210,
  0xAAAAAAAABBBBBBBB,0xCCCCCCCCDDDDDDDD,0xEEEEEEEEFFFFFFFF,0x1111111122222222,
  0x3333333344444444,0x5555555566666666,0x7777777788888888,0x9999999900000000}};

static const uint64_t P[N_PROTO][HV_W] = {
 {0xAAAAAAAA11111111,0xBBBBBBBB22222222,0xCCCCCCCC33333333,0xDDDDDDDD44444444,
  0xEEEEEEEE55555555,0xFFFFFFFF66666666,0x0000000077777777,0x1111111188888888,
  0xAAAAAAAABBBBBBBB,0xCCCCCCCCDDDDDDDD,0xEEEEEEEEFFFFFFFF,0x1111111122222222,
  0x3333333344444444,0x5555555566666666,0x7777777788888888,0x9999999900000000},
 {0x0F1E2D3C4B5A6978,0x0011223344556677,0x8899AABBCCDDEEFF,0xFFEEDDCCBBAA9988,
  0x7766554433221100,0x0123456789ABCDEF,0xFEDCBA9876543210,0xDEADBEEFCAFEBABE,
  0x1111111122222222,0x3333333344444444,0x5555555566666666,0x7777777788888888,
  0x99999999AAAAAAAA,0xBBBBBBBBCCCCCCCC,0xDDDDDDDDEEEEEEEE,0xFFFFFFFFFF000000},
 {0xDEADBEEFCAFEBABE,0x1234567890ABCDEF,0xFEDCBA9876543210,0x0F1E2D3C4B5A6978,
  0x0011223344556677,0x8899AABBCCDDEEFF,0xFFEEDDCCBBAA9988,0x7766554433221100,
  0x0123456789ABCDEF,0xFEDCBA9876543210,0xDEADBEEFCAFEBABE,0x0F1E2D3C4B5A6978,
  0x8899AABBCCDDEEFF,0x0011223344556677,0xFFEEDDCCBBAA9988,0x7766554433221100},
 {0x5555555566666666,0x7777777788888888,0x99999999AAAAAAAA,0xBBBBBBBBCCCCCCCC,
  0xDDDDDDDDEEEEEEEE,0xFFFFFFFFFF000000,0x0000000011111111,0x2222222233333333,
  0x4444444455555555,0x6666666677777777,0x8888888899999999,0xAAAAAAAABBBBBBBB,
  0xCCCCCCCCDDDDDDDD,0xEEEEEEEEFFFFFFFF,0xAAAAAAAABBBBBBBB,0xCCCCCCCCDDDDDDDD}};

// =============================================================================
#if MODE == 0  // ── SW_HDC ────────────────────────────────────────────────────
int main(void) {
    uint64_t acc[HV_W], bind[HV_W], c0,c1,i0,i1;
    c0=rdcycle(); i0=rdinstret();
    for(int p=0;p<N_PROTO;p++){ for(int w=0;w<HV_W;w++)acc[w]=0;
     for(int f=0;f<N_FEAT;f++){
      for(int w=0;w<HV_W;w++)bind[w]=F[f][w]^P[p][w];
      for(int w=0;w<HV_W;w++)acc[w]+=bind[w];
      for(int w=0;w<HV_W;w++){ uint64_t v=acc[w],c=0;
       for(int b=0;b<64;b++)if((v>>b)&1)c|=1ULL<<b; acc[w]=c; }}
     uint64_t d=0; for(int w=0;w<HV_W;w++)
      for(int b=0;b<64;b++)if((acc[w]>>b)&1)d++; }
    c1=rdcycle(); i1=rdinstret();
    finish(((c1-c0)&0xFFFF)|(((i1-i0)&0xFFFF)<<16));
}

#elif MODE == 1  // ── SW_ECC ──────────────────────────────────────────────────
int main(void) {
    uint64_t A[ECC_W]={~0ULL,~0ULL,~0ULL,~0ULL}, Acc[ECC_W]={0,0,0,0};
    uint64_t k=0xDEADBEEFCAFEBABEULL, c0,c1,i0,i1;
    c0=rdcycle(); i0=rdinstret();
    for(int loop=0;loop<256;loop++){
        if(k&1){ for(int i=0;i<ECC_W;i++)Acc[i]^=A[i]; }
        k>>=1; uint64_t msb=A[ECC_W-1]>>63;
        for(int i=ECC_W-1;i>0;i--)A[i]=(A[i]<<1)|(A[i-1]>>63);
        A[0]=A[0]<<1; if(msb)A[0]^=0x425ULL;
    }
    c1=rdcycle(); i1=rdinstret();
    finish(((c1-c0)&0xFFFF)|(((i1-i0)&0xFFFF)<<16));
}

#elif MODE == 2  // ── HW_HDC ──────────────────────────────────────────────────
#define INGEST(rd,rs1,rs2)  asm(".insn r 0x0B,3,0,%0,%1,%2":"=r"(rd):"r"(rs1),"r"(rs2))
#define BIND(rd,rs1)         asm(".insn r 0x0B,0,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define MATCH(rd,rs1)        asm(".insn r 0x0B,2,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define BUNDLE(rd,rs1)       asm(".insn r 0x0B,1,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define CLR_CNT(rd)           asm(".insn r 0x0B,1,1,%0,zero,zero":"=r"(rd))
#define VRF(vd,vs1,vs2)       (((vd)<<10)|((vs1)<<5)|(vs2))
int main(void) {
    uint64_t d, c0,c1,i0,i1;
    for(int f=0;f<N_FEAT;f++)for(int w=0;w<4;w++) INGEST(d,F[f][w],f);
    for(int p=0;p<N_PROTO;p++)for(int w=0;w<4;w++) INGEST(d,P[p][w],N_FEAT+p);
    c0=rdcycle(); i0=rdinstret();
    for(int p=0;p<N_PROTO;p++){for(int f=0;f<N_FEAT;f++)BIND(d,VRF(8+f,f,N_FEAT+p));
     CLR_CNT(d);for(int f=0;f<N_FEAT;f++)BUNDLE(d,VRF(12,8+f,0));
     for(int f=0;f<N_FEAT;f++)MATCH(d,VRF(0,12,N_FEAT+p));}
    c1=rdcycle(); i1=rdinstret();
    finish(((c1-c0)&0xFFFF)|(((i1-i0)&0xFFFF)<<16));
}

#elif MODE == 3  // ── HW_ECC ──────────────────────────────────────────────────
#define ECC_START(rd,rs1) asm(".insn r 0x0B,6,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define ECC_FETCH(rd)     asm(".insn r 0x0B,7,0,%0,zero,zero":"=r"(rd))
int main(void) {
    uint64_t d, c0,c1,i0,i1;
    c0=rdcycle(); i0=rdinstret();
    ECC_START(d,0xDEADBEEFCAFEBABEULL);
    for(volatile int i=0;i<1024;i++)asm("nop");
    ECC_FETCH(d);
    c1=rdcycle(); i1=rdinstret();
    finish(((c1-c0)&0xFFFF)|(((i1-i0)&0xFFFF)<<16));
}

#elif MODE == 4  // ── HW_FUSED ────────────────────────────────────────────────
#define INGEST(rd,rs1,rs2)  asm(".insn r 0x0B,3,0,%0,%1,%2":"=r"(rd):"r"(rs1),"r"(rs2))
#define BIND(rd,rs1)         asm(".insn r 0x0B,0,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define MATCH(rd,rs1)        asm(".insn r 0x0B,2,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define BUNDLE(rd,rs1)       asm(".insn r 0x0B,1,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define CLR_CNT(rd)           asm(".insn r 0x0B,1,1,%0,zero,zero":"=r"(rd))
#define ECC_START(rd,rs1)    asm(".insn r 0x0B,6,0,%0,%1,zero":"=r"(rd):"r"(rs1))
#define ECC_FETCH(rd)        asm(".insn r 0x0B,7,0,%0,zero,zero":"=r"(rd))
#define VRF(vd,vs1,vs2)       (((vd)<<10)|((vs1)<<5)|(vs2))
int main(void) {
    uint64_t d, c0,c1,i0,i1;
    for(int f=0;f<N_FEAT;f++)for(int w=0;w<4;w++) INGEST(d,F[f][w],f);
    for(int p=0;p<N_PROTO;p++)for(int w=0;w<4;w++) INGEST(d,P[p][w],N_FEAT+p);
    c0=rdcycle(); i0=rdinstret();
    ECC_START(d,0xDEADBEEFCAFEBABEULL);
    for(int p=0;p<N_PROTO;p++){for(int f=0;f<N_FEAT;f++)BIND(d,VRF(8+f,f,N_FEAT+p));
     CLR_CNT(d);for(int f=0;f<N_FEAT;f++)BUNDLE(d,VRF(12,8+f,0));
     for(int f=0;f<N_FEAT;f++)MATCH(d,VRF(0,12,N_FEAT+p));}
    for(volatile int i=0;i<1024;i++)asm("nop");
    ECC_FETCH(d);
    c1=rdcycle(); i1=rdinstret();
    finish(((c1-c0)&0xFFFF)|(((i1-i0)&0xFFFF)<<16));
}
#endif
