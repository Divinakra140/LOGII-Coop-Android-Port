// rom_catalog.cpp - "--catalogue DIR": everything the world builder can use,
// read from the player's own game and written to DIR (nothing is shipped):
//   maps.csv       every map: zone, area, place name, size, layers, exits, objects
//   objects.csv    every object record: enemies, people, things (with positions)
//   strings.txt    the game's text table (names, items, techniques, places)
//   maps/*.png     each map drawn from the game (all its layers)
//   tiles/*.png    every distinct map tile of the game (pink = see-through)
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include "map_builder.h"
#include "rom_tiles.h"

namespace romcat {
namespace {
// minimal PNG writer (no zlib needed): one deflate block with the fixed
// Huffman codes and a small LZ77 matcher - maps are very repetitive
struct BitW {
    std::vector<uint8_t>* o; uint32_t acc = 0; int n = 0;
    void put(uint32_t v, int bits) { acc |= v << n; n += bits; while (n >= 8) { o->push_back(static_cast<uint8_t>(acc)); acc >>= 8; n -= 8; } }
    void huff(uint32_t code, int bits) { uint32_t r = 0; for (int i = 0; i < bits; ++i) r |= ((code >> i) & 1u) << (bits - 1 - i); put(r, bits); }
    void flush() { if (n) o->push_back(static_cast<uint8_t>(acc)); acc = 0; n = 0; }
};
void lit(BitW& w, int c) {
    if (c < 144) w.huff(0x30 + c, 8); else if (c < 256) w.huff(0x190 + (c - 144), 9);
    else if (c < 280) w.huff(c - 256, 7); else w.huff(0xC0 + (c - 280), 8);
}
void deflate_fixed(const std::vector<uint8_t>& in, std::vector<uint8_t>* out) {
    static const int lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    static const int lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    static const int dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    static const int dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    BitW w{out};
    w.put(1, 1); w.put(1, 2);   // final block, fixed codes
    const size_t n = in.size();
    std::vector<int> head(1 << 15, -1), prev(n, -1);
    auto hash = [&](size_t i) { return ((in[i] << 10) ^ (in[i + 1] << 5) ^ in[i + 2]) & 0x7FFF; };
    size_t i = 0;
    while (i < n) {
        int best = 0, bd = 0;
        if (i + 3 <= n) {
            const int h = hash(i);
            int c = head[static_cast<size_t>(h)], tries = 32;
            while (c >= 0 && tries-- > 0 && i - static_cast<size_t>(c) <= 32768) {
                int l = 0; const int maxl = static_cast<int>(std::min<size_t>(258, n - i));
                while (l < maxl && in[static_cast<size_t>(c) + l] == in[i + l]) ++l;
                if (l > best) { best = l; bd = static_cast<int>(i - static_cast<size_t>(c)); if (l == maxl) break; }
                c = prev[static_cast<size_t>(c)];
            }
        }
        const size_t step = best >= 3 ? static_cast<size_t>(best) : 1;
        if (best >= 3) {
            int k = 28; while (lbase[k] > best) --k;
            lit(w, 257 + k); w.put(static_cast<uint32_t>(best - lbase[k]), lext[k]);
            int d = 29; while (dbase[d] > bd) --d;
            w.huff(static_cast<uint32_t>(d), 5); w.put(static_cast<uint32_t>(bd - dbase[d]), dext[d]);
        } else lit(w, in[i]);
        for (size_t j = 0; j < step; ++j, ++i)
            if (i + 3 <= n) { const int h = hash(i); prev[i] = head[static_cast<size_t>(h)]; head[static_cast<size_t>(h)] = static_cast<int>(i); }
    }
    lit(w, 256);
    w.flush();
}
void put32(std::vector<uint8_t>& v, uint32_t x) { for (int i = 3; i >= 0; --i) v.push_back(static_cast<uint8_t>(x >> (8 * i))); }
uint32_t crc(const uint8_t* p, size_t n, uint32_t c = 0) {
    c = ~c;
    for (size_t i = 0; i < n; ++i) { c ^= p[i]; for (int k = 0; k < 8; ++k) c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1u))); }
    return ~c;
}
bool write_png_n(const std::string& path, const std::vector<uint8_t>& rgb, int w, int h, int ch) {
    std::vector<uint8_t> raw;
    raw.reserve(static_cast<size_t>(h) * (w * ch + 1));
    for (int y = 0; y < h; ++y) { raw.push_back(0); raw.insert(raw.end(), rgb.begin() + static_cast<long>(y) * w * ch, rgb.begin() + static_cast<long>(y + 1) * w * ch); }
    std::vector<uint8_t> z{0x78, 0x01};
    uint32_t a = 1, b = 0;
    for (uint8_t c : raw) { a = (a + c) % 65521u; b = (b + a) % 65521u; }
    deflate_fixed(raw, &z);
    put32(z, (b << 16) | a);
    std::vector<uint8_t> f{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    auto chunk = [&](const char* t, const std::vector<uint8_t>& d) {
        put32(f, static_cast<uint32_t>(d.size()));
        std::vector<uint8_t> td(t, t + 4); td.insert(td.end(), d.begin(), d.end());
        f.insert(f.end(), td.begin(), td.end()); put32(f, crc(td.data(), td.size()));
    };
    std::vector<uint8_t> ih; put32(ih, static_cast<uint32_t>(w)); put32(ih, static_cast<uint32_t>(h));
    ih.insert(ih.end(), {8, static_cast<uint8_t>(ch == 4 ? 6 : ch == 1 ? 0 : 2), 0, 0, 0});
    chunk("IHDR", ih); chunk("IDAT", z); chunk("IEND", {});
    std::ofstream o(path, std::ios::binary);
    o.write(reinterpret_cast<const char*>(f.data()), static_cast<std::streamsize>(f.size()));
    return static_cast<bool>(o);
}
bool write_png(const std::string& path, const std::vector<uint8_t>& rgb, int w, int h) { return write_png_n(path, rgb, w, h, 3); }
std::string csv(std::string s) { std::replace(s.begin(), s.end(), ',', ';'); return s; }
const char* kind_name(uint32_t h) {
    switch (h) { case 0x0800E77Fu: return "enemy"; case 0x0800B711u: return "person"; case 0x0800D6DFu: return "thing"; default: return "other"; }
}
}  // namespace

// one area as it is now (the live map table: a new floor if one is switched in), all its layers
bool draw_area(const mapbuild::Rom& rom, int z, int a, std::vector<uint8_t>* img, int* W, int* H,
               std::vector<uint8_t>* walk, std::vector<mapbuild::Rect>* exits) {
    mapbuild::SrcMap sm;
    if (!mapbuild::load_src(rom, z, a, &sm) || sm.tw <= 0 || sm.th <= 0) return false;
    uint8_t pal[768]; romtiles::palette_rgb(pal);
    *W = sm.tw * 8; *H = sm.th * 8;
    img->assign(static_cast<size_t>(*W) * *H * 3, 0);
    for (size_t i = 0; i < img->size(); i += 3) { (*img)[i] = pal[0]; (*img)[i + 1] = pal[1]; (*img)[i + 2] = pal[2]; }
    int order[4] = {0, 1, 2, 3};
    std::sort(order, order + 4, [&](int x, int y) { return sm.pri[x] != sm.pri[y] ? sm.pri[x] > sm.pri[y] : x > y; });
    for (int oi = 0; oi < 4; ++oi) {
        const int k = order[oi];
        if (sm.L[k].empty()) continue;
        for (int ty = 0; ty < sm.th; ++ty) for (int tx = 0; tx < sm.tw; ++tx) {
            const uint16_t e = sm.L[k][static_cast<size_t>(ty) * sm.tw + tx];
            const uint8_t* t = (e & 0x3FF) ? romtiles::map_tile(z, a, e & 0x3FF) : nullptr;
            if (!t) continue;
            for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
                const int sx = (e & 0x400) ? 7 - x : x, sy = (e & 0x800) ? 7 - y : y;
                const uint8_t c = t[sy * 8 + sx];
                if (!c) continue;
                uint8_t* p = &(*img)[(static_cast<size_t>(ty * 8 + y) * *W + tx * 8 + x) * 3];
                p[0] = pal[c * 3]; p[1] = pal[c * 3 + 1]; p[2] = pal[c * 3 + 2];
            }
        }
    }
    if (walk) { walk->assign(static_cast<size_t>(sm.tw) * sm.th, 1); if (sm.wa.size() == walk->size()) *walk = sm.wa; }
    if (exits) *exits = sm.exits;
    return true;
}
bool save_png(const std::string& path, const std::vector<uint8_t>& rgb, int w, int h) { return write_png(path, rgb, w, h); }
bool save_png_rgba(const std::string& path, const std::vector<uint8_t>& rgba, int w, int h) { return write_png_n(path, rgba, w, h, 4); }
bool save_png_gray(const std::string& path, const std::vector<uint8_t>& g, int w, int h) { return write_png_n(path, g, w, h, 1); }

int run(const std::string& rom_path, const std::string& dir) {
    std::ifstream in(rom_path, std::ios::binary);
    std::vector<uint8_t> romv((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (romv.size() < 0x400000) { std::fprintf(stderr, "[catalogue] cannot read the game: %s\n", rom_path.c_str()); return 1; }
    const mapbuild::Rom rom{romv.data(), romv.size()};
    romtiles::init(rom);
    namespace fs = std::filesystem;
    std::error_code ec;
    fs::create_directories(fs::path(dir) / "maps", ec);
    fs::create_directories(fs::path(dir) / "tiles", ec);
    uint8_t pal[768]; romtiles::palette_rgb(pal);
    // strings
    {
        std::ofstream s((fs::path(dir) / "strings.txt").string());
        for (int i = 0; i < 4000; ++i) {
            const std::string t = romtiles::game_string(i);
            if (t.empty() && i > 400) break;
            std::string e; for (char c : t) e += c == '\n' ? std::string("\\n") : std::string(1, c);
            s << i << '\t' << e << '\n';
        }
    }
    std::ofstream mc((fs::path(dir) / "maps.csv").string());
    std::ofstream oc((fs::path(dir) / "objects.csv").string());
    mc << "zone,area,place,width,height,layers,exits,enemies,people,things,other,tile_slots\n";
    oc << "zone,area,kind,handler,x,y,type\n";
    int drawn = 0;
    for (const auto& m : romtiles::maps()) {
        mapbuild::SrcMap sm;
        if (!mapbuild::load_src(rom, m.z, m.a, &sm)) continue;
        int layers = 0;
        for (int k = 0; k < 4; ++k) if (rom.ok(rom.r32(m.var + 0x14 + 4u * static_cast<uint32_t>(k)), 0x18)) ++layers;
        int cnt[4] = {0, 0, 0, 0};
        const uint32_t l = rom.r32(m.entry + 0x14);
        if (rom.ok(l, 4))
            for (uint32_t k = 0; k < 64; ++k) {
                const uint32_t r = rom.r32(l + 4 * k);
                if (!rom.ok(r, 0x14)) break;
                const uint32_t h = rom.r32(r);
                if ((h >> 24) != 0x08) break;   // end of the list
                const char* kn = kind_name(h);
                const int ki = !std::strcmp(kn, "enemy") ? 0 : !std::strcmp(kn, "person") ? 1 : !std::strcmp(kn, "thing") ? 2 : 3;
                ++cnt[ki];
                const uint32_t pos = rom.r32(r + (ki == 0 ? 0xC : 8));
                char line[160];
                std::snprintf(line, sizeof line, "%d,%d,%s,0x%08X,%u,%u,0x%X\n", m.z, m.a, kn, h, pos & 0xFFFF, pos >> 16, ki == 0 ? rom.r32(r + 8) : rom.r32(r + 0x10));
                oc << line;
            }
        mc << m.z << ',' << m.a << ',' << csv(romtiles::place_name(m.z, m.a)) << ',' << sm.tw * 8 << ',' << sm.th * 8 << ','
           << layers << ',' << sm.exits.size() << ',' << cnt[0] << ',' << cnt[1] << ',' << cnt[2] << ',' << cnt[3] << ',' << romtiles::slot_count(m.z, m.a) << '\n';
        // the picture: back layers first (priority from the variant header)
        const int W = sm.tw * 8, H = sm.th * 8;
        std::vector<uint8_t> img(static_cast<size_t>(W) * H * 3);
        for (size_t i = 0; i < img.size(); i += 3) { img[i] = pal[0]; img[i + 1] = pal[1]; img[i + 2] = pal[2]; }
        int order[4] = {0, 1, 2, 3};
        std::sort(order, order + 4, [&](int x, int y) { const int px = rom.r8(m.var + 4 + static_cast<uint32_t>(x)) & 3, py = rom.r8(m.var + 4 + static_cast<uint32_t>(y)) & 3; return px != py ? px > py : x > y; });
        for (int oi = 0; oi < 4; ++oi) {
            const int k = order[oi];
            if (sm.L[k].empty()) continue;
            for (int ty = 0; ty < sm.th; ++ty) for (int tx = 0; tx < sm.tw; ++tx) {
                const uint16_t e = sm.L[k][static_cast<size_t>(ty) * sm.tw + tx];
                const uint8_t* t = romtiles::map_tile(m.z, m.a, e & 0x3FF);
                if (!t || !(e & 0x3FF)) continue;
                for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
                    const int sx = (e & 0x400) ? 7 - x : x, sy = (e & 0x800) ? 7 - y : y;
                    const uint8_t c = t[sy * 8 + sx];
                    if (!c) continue;
                    uint8_t* p = &img[(static_cast<size_t>(ty * 8 + y) * W + tx * 8 + x) * 3];
                    p[0] = pal[c * 3]; p[1] = pal[c * 3 + 1]; p[2] = pal[c * 3 + 2];
                }
            }
        }
        char name[64]; std::snprintf(name, sizeof name, "z%02d_a%03d.png", m.z, m.a);
        if (write_png((fs::path(dir) / "maps" / name).string(), img, W, H)) ++drawn;
    }
    // every distinct tile, 32 per row, in id order
    {
        std::vector<uint16_t> idsv;
        for (uint16_t id = 1; id < 0xC000; ++id) { if (!romtiles::tile(id)) break; idsv.push_back(id); }
        const int per = 64, rows = static_cast<int>((idsv.size() + per - 1) / per);
        for (int part = 0; part * 64 < rows; ++part) {
            const int r0 = part * 64, r1 = std::min(rows, r0 + 64);
            const int W = per * 8, H = (r1 - r0) * 8;
            std::vector<uint8_t> img(static_cast<size_t>(W) * H * 3, 0);
            for (int r = r0; r < r1; ++r) for (int c = 0; c < per; ++c) {
                const size_t i = static_cast<size_t>(r) * per + c;
                if (i >= idsv.size()) break;
                const uint8_t* t = romtiles::tile(idsv[i]);
                for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
                    const uint8_t cc = t[y * 8 + x];
                    uint8_t* p = &img[(static_cast<size_t>((r - r0) * 8 + y) * W + c * 8 + x) * 3];
                    if (cc) { p[0] = pal[cc * 3]; p[1] = pal[cc * 3 + 1]; p[2] = pal[cc * 3 + 2]; } else { p[0] = 255; p[1] = 0; p[2] = 255; }
                }
            }
            char name[64]; std::snprintf(name, sizeof name, "tiles_%02d.png", part);
            write_png((fs::path(dir) / "tiles" / name).string(), img, W, H);
        }
        std::fprintf(stderr, "[catalogue] %zu distinct tiles\n", idsv.size());
    }
    std::fprintf(stderr, "[catalogue] %zu maps (%d pictures) written to %s\n", romtiles::maps().size(), drawn, dir.c_str());
    return 0;
}
}  // namespace romcat
