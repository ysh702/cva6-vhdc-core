// =============================================================================
// tb_gf2_256_diag_mul_raw.cpp — C++ Verilator testbench
// =============================================================================
// Reads test vectors from text file at runtime.
// Verilator 5.x: wide ports accessed via 32-bit IData word arrays.
// =============================================================================

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <iostream>
#include "verilated.h"
#include "Vgf2_256_diag_mul_raw.h"

struct TestVector {
    int index;
    std::string comment;
    uint64_t a[4];
    uint64_t b[4];
    uint64_t prod[8];
};

// Parse 64-char hex string into 4 uint64_t (little-endian: word 0 = bits 63:0)
static bool parse_hex256(const std::string &hex, uint64_t out[4]) {
    if (hex.length() != 64) return false;
    for (int i = 0; i < 4; i++) {
        std::string chunk = hex.substr(48 - i*16, 16);
        out[i] = strtoull(chunk.c_str(), nullptr, 16);
    }
    return true;
}

// Parse 128-char hex string into 8 uint64_t
static bool parse_hex512(const std::string &hex, uint64_t out[8]) {
    if (hex.length() != 128) return false;
    for (int i = 0; i < 8; i++) {
        std::string chunk = hex.substr(112 - i*16, 16);
        out[i] = strtoull(chunk.c_str(), nullptr, 16);
    }
    return true;
}

static std::vector<TestVector> load_vectors(const std::string &path) {
    std::vector<TestVector> vecs;
    std::ifstream f(path);
    if (!f.is_open()) {
        std::cerr << "ERROR: cannot open " << path << std::endl;
        return vecs;
    }
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream iss(line);
        TestVector tv;
        std::string a_hex, b_hex, prod_hex;
        if (!(iss >> tv.index >> tv.comment >> a_hex >> b_hex >> prod_hex)) continue;
        if (!parse_hex256(a_hex, tv.a) || !parse_hex256(b_hex, tv.b) || !parse_hex512(prod_hex, tv.prod)) {
            std::cerr << "ERROR: bad parse at vector " << tv.index << std::endl;
            continue;
        }
        vecs.push_back(tv);
    }
    return vecs;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    const char *vec_path = "tools/hdec/ecc_diag_mul_vectors.txt";
    if (argc > 1) vec_path = argv[1];

    std::vector<TestVector> vectors = load_vectors(vec_path);
    if (vectors.empty()) {
        std::cerr << "ERROR: no vectors loaded from " << vec_path << std::endl;
        return 1;
    }
    printf("Loaded %zu test vectors from %s\n", vectors.size(), vec_path);

    Vgf2_256_diag_mul_raw *dut = new Vgf2_256_diag_mul_raw;

    // Helper: set 256-bit port from 64-bit word array (LSB in word 0)
    auto set_256bit = [&](const uint64_t src[4]) {
        for (int i = 0; i < 4; i++) {
            uint64_t w = src[i];
            dut->a_i[i*2 + 0] = (uint32_t)(w & 0xFFFFFFFFULL);
            dut->a_i[i*2 + 1] = (uint32_t)((w >> 32) & 0xFFFFFFFFULL);
        }
    };

    auto set_b_256bit = [&](const uint64_t src[4]) {
        for (int i = 0; i < 4; i++) {
            uint64_t w = src[i];
            dut->b_i[i*2 + 0] = (uint32_t)(w & 0xFFFFFFFFULL);
            dut->b_i[i*2 + 1] = (uint32_t)((w >> 32) & 0xFFFFFFFFULL);
        }
    };

    // Helper: read 511-bit product from 32-bit words into 64-bit words
    auto read_product = [&](uint64_t out[8]) {
        for (int i = 0; i < 8; i++) {
            uint64_t lo = dut->product_o[i*2 + 0];
            uint64_t hi = dut->product_o[i*2 + 1];
            out[i] = lo | (hi << 32);
        }
        out[7] &= 0x7FFFFFFFFFFFFFFFULL;
    };

    // ── Initialise ───────────────────────────────────────────────────────────
    dut->clk_i   = 0;
    dut->rst_ni  = 0;
    dut->start_i = 0;
    for (int i = 0; i < 8; i++) { dut->a_i[i] = 0; dut->b_i[i] = 0; }

    // ── Reset ────────────────────────────────────────────────────────────────
    for (int i = 0; i < 10; i++) {
        dut->clk_i = 0; dut->eval();
        dut->clk_i = 1; dut->eval();
    }
    dut->rst_ni = 1;
    for (int i = 0; i < 3; i++) {
        dut->clk_i = 0; dut->eval();
        dut->clk_i = 1; dut->eval();
    }

    // ── Run vectors ──────────────────────────────────────────────────────────
    int passed  = 0;
    int failed  = 0;
    int timeouts = 0;

    for (size_t vi = 0; vi < vectors.size(); vi++) {
        const TestVector &tv = vectors[vi];

        set_256bit(tv.a);
        set_b_256bit(tv.b);

        // Assert start for one cycle
        dut->start_i = 1;
        dut->clk_i = 0; dut->eval();
        dut->clk_i = 1; dut->eval();
        dut->start_i = 0;

        // Wait for done_o (max 600 cycles)
        int cycles = 0;
        bool done_seen = false;
        while (cycles < 600) {
            dut->clk_i = 0; dut->eval();
            dut->clk_i = 1; dut->eval();
            cycles++;
            if (dut->done_o) {
                done_seen = true;
                break;
            }
        }

        if (!done_seen) {
            printf("TIMEOUT: vector %d (%s) — no done after 600 cycles\n",
                   tv.index, tv.comment.c_str());
            timeouts++;
            dut->rst_ni = 0;
            for (int i = 0; i < 3; i++) {
                dut->clk_i = 0; dut->eval();
                dut->clk_i = 1; dut->eval();
            }
            dut->rst_ni = 1;
            continue;
        }

        uint64_t got[8];
        read_product(got);

        bool match = true;
        int first_bad = -1;
        for (int w = 0; w < 8; w++) {
            if (got[w] != tv.prod[w]) {
                match = false;
                uint64_t diff = got[w] ^ tv.prod[w];
                for (int b = 0; b < 64; b++) {
                    if ((diff >> b) & 1) { first_bad = w * 64 + b; break; }
                }
                break;
            }
        }

        if (match) {
            passed++;
        } else {
            failed++;
            printf("FAIL: vector %d (%s)\n", tv.index, tv.comment.c_str());
            printf("  a        = ");
            for (int i = 3; i >= 0; i--) printf("%016llx", (unsigned long long)tv.a[i]);
            printf("\n  b        = ");
            for (int i = 3; i >= 0; i--) printf("%016llx", (unsigned long long)tv.b[i]);
            printf("\n  expected = ");
            for (int i = 7; i >= 0; i--) printf("%016llx", (unsigned long long)tv.prod[i]);
            printf("\n  got      = ");
            for (int i = 7; i >= 0; i--) printf("%016llx", (unsigned long long)got[i]);
            printf("\n  first bad bit = %d\n", first_bad);
            printf("  done latency  = %d cycles\n", cycles);
        }

        // One idle cycle
        dut->clk_i = 0; dut->eval();
        dut->clk_i = 1; dut->eval();
    }

    dut->final();

    printf("\nRESULTS: %d passed, %d failed, %d timeout\n", passed, failed, timeouts);
    if (failed == 0 && timeouts == 0) {
        printf("PASS: gf2_256_diag_mul_raw matched all vectors\n");
        return 0;
    } else {
        printf("FAIL: %d vector(s) mismatched\n", failed);
        return 1;
    }
}
