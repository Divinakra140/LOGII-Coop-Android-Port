// rom_sprites.cpp - see rom_sprites.h.
#include "rom_sprites.h"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>

namespace log2rom {
namespace {

constexpr std::uint32_t kSpriteSets = 0x083B4E74u;
constexpr std::uint32_t kObjPalette = 0x081DA6C8u;   // 256 x BGR555

// Bit reader matching the ARM routine: 32-bit little-endian words consumed
// most-significant bit first; r10 = bits left in the current word.
struct Bits {
    const std::uint8_t* p;
    const std::uint8_t* end;
    std::uint32_t buf = 0;
    int left = 0;
    std::uint32_t word() {
        std::uint32_t v = 0;
        if (p + 4 <= end) std::memcpy(&v, p, 4);
        p += 4;
        return v;
    }
    // the inlined "subs r10,#1 / ldrmi / movmi #31 / adds r6,r6,r6" sequence
    std::uint32_t bit() {
        if (--left < 0) { buf = word(); left = 31; }
        const std::uint32_t c = buf >> 31;
        buf <<= 1;
        return c;
    }
    // subroutine at 0x0300024C (r8 = n)
    std::uint32_t get(std::uint32_t n) {
        if (n == 0) return 0;
        if (left == 0) { buf = word(); left = 32; }
        const std::uint32_t take = std::min<std::uint32_t>(n, static_cast<std::uint32_t>(left));
        std::uint32_t r = take ? static_cast<std::uint32_t>(static_cast<std::uint64_t>(buf) >> (32 - take)) : 0;
        buf = take >= 32 ? 0 : buf << take;
        left -= static_cast<int>(take);
        n -= take;
        if (n == 0) return r;
        buf = word();
        left = 32 - static_cast<int>(n);
        const std::uint32_t hi = static_cast<std::uint32_t>(static_cast<std::uint64_t>(buf) >> left);
        r = hi + static_cast<std::uint32_t>(static_cast<std::uint64_t>(r) << n);
        buf = n >= 32 ? 0 : buf << n;
        return r;
    }
    std::uint32_t gamma() {             // r9 = 1; do r9 = 2*r9 + bit; while bit
        std::uint32_t v = 1;
        do { v = v * 2 + bit(); } while (bit());
        return v;
    }
};

}  // namespace

void decompress(const std::uint8_t* src, std::size_t src_len, std::uint32_t lit_bits,
                std::uint8_t* dst, std::size_t dst_len) {
    Bits b{src, src + src_len};
    std::size_t o = 0;
    std::uint32_t off_bits = 8;    // r5
    std::uint32_t last = 1;        // r12
    std::uint32_t base = 0;        // r4
    std::uint32_t width = lit_bits;// r3
    auto put = [&](std::uint32_t v) { if (o < dst_len) dst[o] = static_cast<std::uint8_t>(v); ++o; };
    auto back = [&](std::uint32_t d) -> std::uint8_t { return (d <= o && o - d < dst_len) ? dst[o - d] : 0; };
    auto copy = [&](std::uint32_t dist, std::uint32_t n) { while (n--) put(back(dist)); };
    int guard = 0;
    while (o < dst_len + 8 && ++guard < (1 << 22)) {
        if (b.bit()) {                         // literal: base + width bits
            put(b.get(width) + base);
            continue;
        }
        if (b.bit()) {                         // 0x13C: gamma-coded match
            std::uint32_t n = b.gamma();
            if (n == 2) {                      // repeat last distance
                copy(last, b.gamma());
                continue;
            }
            n -= 3;
            const std::uint32_t lo = b.get(off_bits);
            last = lo + static_cast<std::uint32_t>(static_cast<std::uint64_t>(n) << off_bits);
            std::uint32_t len = b.gamma();
            if (last >= 0x10000u) len += 3;
            else if (last >= 0x37FFu) len += 2;
            else if (last >= 0x27Fu) len += 1;
            else if (last <= 127u) len += 4;
            copy(last, len);
            continue;
        }
        if (!b.bit()) {                        // 0xF0: short match / control
            const std::uint32_t d = b.get(7);
            if (d != 0) {
                last = d;
                copy(d, b.get(2) + 2);
                continue;
            }
            const std::uint32_t c = b.get(2);
            if (c == 0) break;                 // end of stream
            off_bits = b.get(c + 3);
            continue;
        }
        // 0x60: 4-bit near copy / zero / raw runs / literal mode switch
        const std::int32_t v = static_cast<std::int32_t>(b.get(4)) - 1;
        if (v == 0) { put(0); continue; }
        if (v > 0) { put(back(static_cast<std::uint32_t>(v))); continue; }
        if (b.bit()) {                         // raw 256-byte blocks
            do {
                for (int i = 0; i < 256; ++i) put(b.get(8));
            } while (b.bit());
            continue;
        }
        base = 0;
        width = 7 + b.bit();
        if (width != 8) base = b.get(8);
    }
}

std::uint32_t Sprites::u32(std::uint32_t addr) const {
    const std::uint32_t o = addr - 0x08000000u;
    if (addr < 0x08000000u || o + 4 > rom_.size()) return 0;
    std::uint32_t v;
    std::memcpy(&v, &rom_[o], 4);
    return v;
}

bool Sprites::rom_ptr(std::uint32_t v) const {
    return v >= 0x08000000u && v - 0x08000000u < rom_.size();
}

bool Sprites::load(const std::string& rom_path) {
    rom_.clear();
    std::ifstream f(rom_path, std::ios::binary);
    if (!f) return false;
    std::vector<std::uint8_t> d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (d.size() < 0x400000 || std::memcmp(&d[0xAC], "ALFE", 4) != 0) return false;   // USA LoG2
    rom_.swap(d);
    for (int i = 0; i < 256; ++i) {
        const std::uint32_t a = kObjPalette - 0x08000000u + 2u * static_cast<std::uint32_t>(i);
        const std::uint16_t c = static_cast<std::uint16_t>(rom_[a] | (rom_[a + 1] << 8));
        const std::uint32_t r = (c & 31u) << 3, g = ((c >> 5) & 31u) << 3, bl = ((c >> 10) & 31u) << 3;
        pal_[i] = 0xFF000000u | (bl << 16) | (g << 8) | r;
    }
    return true;
}

int Sprites::frame_count(int set, int anim, int dir) const {
    if (!ok()) return 0;
    const std::uint32_t s = u32(kSpriteSets + 4u * static_cast<std::uint32_t>(set));
    if (!rom_ptr(s)) return 0;
    int nslots = 0;
    while (nslots < 48 && rom_ptr(u32(s + 0x4Cu + 4u * nslots))) ++nslots;
    const int slot = anim * 4 + dir;
    if (slot >= nslots) return 0;
    const std::uint32_t a = u32(s + 0x4Cu + 4u * slot);
    std::uint32_t lim = a + 12u * 16u;
    for (int k = 0; k < nslots; ++k) {
        const std::uint32_t x = u32(s + 0x4Cu + 4u * k);
        if (x > a && x < lim) lim = x;
    }
    int n = 0;
    while (a + 12u * n < lim) {
        const std::uint32_t g = u32(a + 12u * n + 8u);
        if (!rom_ptr(g) || u32(g) > 2u || u32(g + 4) == 0 || u32(g + 4) > 0x800u) break;
        ++n;
    }
    return n;
}

bool Sprites::frame(int set, int anim, int dir, int fr, Image* out) const {
    const int n = frame_count(set, anim, dir);
    if (n == 0 || !out) return false;
    fr %= n;
    const std::uint32_t s = u32(kSpriteSets + 4u * static_cast<std::uint32_t>(set));
    const std::uint32_t e = u32(s + 0x4Cu + 4u * static_cast<std::uint32_t>(anim * 4 + dir)) + 12u * static_cast<std::uint32_t>(fr);
    const std::uint32_t attrs = u32(e + 4u), gfx = u32(e + 8u);
    const std::uint32_t type = u32(gfx), size = u32(gfx + 4u);
    static const int kW[3][4] = {{8, 16, 32, 64}, {16, 32, 32, 64}, {8, 8, 16, 32}};
    static const int kH[3][4] = {{8, 16, 32, 64}, {8, 8, 16, 32}, {16, 32, 32, 64}};
    const int shape = static_cast<int>((attrs >> 14) & 3u), sz = static_cast<int>((attrs >> 30) & 3u);
    if (shape > 2) return false;
    const bool bpp8 = (attrs >> 13) & 1u, hflip = (attrs >> 28) & 1u;
    const int w = kW[shape][sz], h = kH[shape][sz];
    std::vector<std::uint8_t> px(std::max<std::uint32_t>(size, 0x800u), 0);
    const std::uint32_t off = gfx - 0x08000000u + 8u;
    if (off >= rom_.size()) return false;
    if (type == 0) std::memcpy(px.data(), &rom_[off], std::min<std::size_t>(size, rom_.size() - off));
    else decompress(&rom_[off], rom_.size() - off, type, px.data(), size);
    out->w = w; out->h = h;
    out->rgba.assign(static_cast<std::size_t>(w * h), 0u);
    const int tw = w / 8, tb = bpp8 ? 64 : 32;
    for (int t = 0; t * tb < static_cast<int>(size) && t / tw < h / 8; ++t) {
        const int tx = t % tw, ty = t / tw;
        for (int y = 0; y < 8; ++y)
            for (int x = 0; x < 8; ++x) {
                int v = bpp8 ? px[static_cast<std::size_t>(t * 64 + y * 8 + x)]
                             : (px[static_cast<std::size_t>(t * 32 + y * 4 + x / 2)] >> ((x & 1) * 4)) & 15;
                if (!v) continue;
                int X = tx * 8 + x;
                if (hflip) X = w - 1 - X;
                out->rgba[static_cast<std::size_t>((ty * 8 + y) * w + X)] = pal_[v];
            }
    }
    return true;
}

}  // namespace log2rom
