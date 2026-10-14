// ---------------------------------------------------------------- the other games' pieces (DEV TOOLS library)
// godot_export library GAME OUTDIR   (GAME: Dragon Ball Z - Buu's Fury (USA) or The Legacy of Goku (any))
// Read from the user's own cartridge, never shipped:
//   OUTDIR/lib/<g>/tiles.png     every distinct map tile of that game (RGBA, rows of 64)      (Buu's Fury)
//   OUTDIR/lib/<g>/maps/Z_A.bin  each map: "LKR2", u16 tw, u16 th, 5 layers of tw*th u32 cells, tw*th walk bytes
//                                cell = tile id | 1<<20 (a library tile) | game << 21 | flips (16 h, 17 v)
//   OUTDIR/lib/<g>/maps.json     {"game", "maps": [{key, name, tw, th}]}
//   OUTDIR/sprites/set_N.png/json  the game's characters as sprite sets the editors use (Buu's Fury 1000+, LoG1 2000+)
//   OUTDIR/lib/<g>/sets.json     {"sets": [{id, slots, name}]}
namespace libx {
struct LR {
    std::vector<uint8_t> d;
    mapbuild::Rom r;
    bool ok(uint32_t a, size_t k = 4) const { return r.ok(a, k); }
    uint32_t w(uint32_t a) const { return r.r32(a); }
    uint16_t h(uint32_t a) const { return r.r16(a); }
    uint8_t b(uint32_t a) const { return r.r8(a); }
};
static uint32_t rgba555(uint16_t c) {
    const uint32_t R = (c & 31u) << 3, G = ((c >> 5) & 31u) << 3, B = ((c >> 10) & 31u) << 3;
    return R | (G << 8) | (B << 16) | 0xFF000000u;
}


// ---- sprite sets (both games): frames as RGBA pictures with their offsets
struct LFrame { int ox = 0, oy = 0, w = 0, h = 0; std::vector<uint32_t> px; };
static void write_set(const fs::path& dir, int id, const std::vector<std::vector<LFrame>>& slots) {
    int maxf = 1;
    for (const auto& s : slots) maxf = std::max(maxf, static_cast<int>(s.size()));
    const int C = 64, W = C * maxf, H = C * static_cast<int>(slots.size());
    std::vector<uint8_t> img(static_cast<size_t>(W) * H * 4, 0);
    std::string js = "{\"set\":" + std::to_string(id) + ",\"cell\":64,\"header\":[],\"slots\":[";
    for (size_t k = 0; k < slots.size(); ++k) {
        js += k ? ",[" : "[";
        for (size_t n = 0; n < slots[k].size(); ++n) {
            const LFrame& f = slots[k][n];
            for (int y = 0; y < f.h && y < C; ++y) for (int x = 0; x < f.w && x < C; ++x) {
                const uint32_t c = f.px[static_cast<size_t>(y * f.w + x)];
                if (!c) continue;
                std::memcpy(&img[((k * C + static_cast<size_t>(y)) * W + n * C + static_cast<size_t>(x)) * 4], &c, 4);
            }
            char b[96]; std::snprintf(b, sizeof b, "%s{\"x\":%d,\"y\":%d,\"w\":%d,\"h\":%d}", n ? "," : "", f.ox, f.oy, std::min(f.w, C), std::min(f.h, C));
            js += b;
        }
        js += "]";
    }
    js += "]}";
    romcat::save_png_rgba((dir / ("set_" + std::to_string(id) + ".png")).string(), img, W, H);
    write_text(dir / ("set_" + std::to_string(id) + ".json"), js);
}

// ================================================================ Buu's Fury (same engine as this game)
static constexpr uint32_t kBfMaps = 0x0808EA18u, kBfTilemap = 0x08008087u, kBfBgPal = 0x0805632Cu, kBfObjPal = 0x0805652Cu;

static bool bf_frame(const LR& R, const uint32_t* opal, uint32_t e, LFrame* f) {
    if (!R.ok(e, 20)) return false;
    const uint32_t w0 = R.w(e + 4), attrs = R.w(e + 12), gfx = R.w(e + 16);
    if (!R.ok(gfx, 8)) return false;
    const uint32_t type = R.w(gfx), size = R.w(gfx + 4);
    if (type > 2 || size == 0 || size > 0x2000) return false;
    static const int kW[3][4] = {{8, 16, 32, 64}, {16, 32, 32, 64}, {8, 8, 16, 32}};
    static const int kH[3][4] = {{8, 16, 32, 64}, {8, 8, 16, 32}, {16, 32, 32, 64}};
    const int shape = static_cast<int>((attrs >> 14) & 3u), sz = static_cast<int>((attrs >> 30) & 3u);
    if (shape > 2) return false;
    const bool bpp8 = (attrs >> 13) & 1u, hf = (attrs >> 28) & 1u, vf = (attrs >> 29) & 1u;
    const int w = kW[shape][sz], h = kH[shape][sz];
    std::vector<uint8_t> px(std::max<uint32_t>(size, 0x800u), 0);
    const size_t off = gfx - 0x08000000u + 8u;
    if (off >= R.d.size()) return false;
    if (type == 0) std::memcpy(px.data(), &R.d[off], std::min<size_t>(size, R.d.size() - off));
    else log2rom::decompress(&R.d[off], R.d.size() - off, type, px.data(), size);
    f->w = w; f->h = h; f->ox = static_cast<int8_t>(w0 & 0xFF); f->oy = static_cast<int8_t>((w0 >> 8) & 0xFF);
    f->px.assign(static_cast<size_t>(w * h), 0u);
    const int tw = w / 8, tb = bpp8 ? 64 : 32;
    for (int t = 0; t * tb < static_cast<int>(size) && t / tw < h / 8; ++t) {
        const int tx = t % tw, ty = t / tw;
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) {
            const int v = bpp8 ? px[static_cast<size_t>(t * 64 + y * 8 + x)] : (px[static_cast<size_t>(t * 32 + y * 4 + x / 2)] >> ((x & 1) * 4)) & 15;
            if (!v) continue;
            int X = tx * 8 + x, Y = ty * 8 + y;
            if (hf) X = w - 1 - X;
            if (vf) Y = h - 1 - Y;
            f->px[static_cast<size_t>(Y * w + X)] = opal[v];
        }
    }
    return true;
}
// an animation: u32 frames n, then n x 4 frame pointers (down, up, left, right)
static bool bf_anim_ok(const LR& R, uint32_t a) {
    if (!R.ok(a, 8)) return false;
    const uint32_t n = R.w(a);
    if (n < 1 || n > 48 || !R.ok(a, 4 + 16 * n)) return false;
    for (uint32_t k = 0; k < 4 * n; ++k) {
        const uint32_t e = R.w(a + 4 + 4 * k);
        if (!R.ok(e, 20) || R.w(e) > 255) return false;
        const uint32_t g = R.w(e + 16), at = R.w(e + 12);
        if (!R.ok(g, 8) || R.w(g) > 2 || R.w(g + 4) == 0 || R.w(g + 4) > 0x2000 || ((at >> 14) & 3u) == 3u) return false;
    }
    return true;
}
static int bf_sprites(const LR& R, const fs::path& out, const fs::path& lib) {
    uint32_t opal[256];
    for (int i = 0; i < 256; ++i) opal[i] = i ? rgba555(R.h(kBfObjPal + 2u * i)) : 0u;
    std::unordered_set<uint32_t> anims;
    const uint32_t end = 0x08000000u + static_cast<uint32_t>(R.d.size()) - 8;
    for (uint32_t a = 0x08000000u; a < end; a += 4) if (R.w(a) - 1u < 48u && bf_anim_ok(R, a)) anims.insert(a);
    // a set: a list of animations (pointers, a few empty ones between)
    std::vector<std::pair<uint32_t, std::vector<uint32_t>>> sets;
    for (uint32_t a = 0x08000000u; a < end; a += 4) {
        if (!anims.count(R.w(a)) || anims.count(R.w(a - 4))) continue;
        std::vector<uint32_t> L; uint32_t q = a; int z = 0;
        while (q < end) {
            const uint32_t v = R.w(q);
            if (anims.count(v)) { while (z > 0) { L.push_back(0); --z; } L.push_back(v); }
            else if (v == 0 && z < 3) ++z;
            else break;
            q += 4;
        }
        if (L.size() >= 4) sets.push_back({a, L});
        a = q - 4;
    }
    fs::create_directories(out);
    std::string js = "{\"game\":\"bf\",\"sets\":[";
    int n = 0;
    for (const auto& [at, L] : sets) {
        std::vector<std::vector<LFrame>> slots;
        for (uint32_t an : L) {
            for (int d = 0; d < 4; ++d) {
                std::vector<LFrame> fr;
                if (an) {
                    const uint32_t nf = std::min<uint32_t>(R.w(an), 16);
                    for (uint32_t i = 0; i < nf; ++i) { LFrame f; if (bf_frame(R, opal, R.w(an + 4 + 4 * (i * 4 + static_cast<uint32_t>(d))), &f)) fr.push_back(std::move(f)); }
                }
                slots.push_back(std::move(fr));
            }
        }
        const int id = 1000 + n;
        write_set(out, id, slots);
        char b[128]; std::snprintf(b, sizeof b, "%s{\"id\":%d,\"slots\":%zu,\"at\":\"%08x\"}", n ? "," : "", id, slots.size(), at);
        js += b;
        ++n;
    }
    write_text(lib / "sets.json", js + "]}");
    return n;
}

static int bf_maps(const LR& R, const fs::path& lib) {
    uint32_t bpal[256];
    for (int i = 0; i < 256; ++i) bpal[i] = rgba555(R.h(kBfBgPal + 2u * i));
    std::map<uint32_t, std::vector<uint8_t>> sheets;     // sheet table + k -> its tiles (8bpp, 64 bytes each)
    auto sheet = [&](uint32_t table, uint32_t k) -> const std::vector<uint8_t>* {
        const uint32_t key = table + 4u * k;
        auto it = sheets.find(key);
        if (it != sheets.end()) return it->second.empty() ? nullptr : &it->second;
        std::vector<uint8_t>& v = sheets[key];
        const uint32_t d = R.w(key);
        if (R.ok(d, 8) && R.w(d) <= 8) mapbuild::decode(R.r, d, &v);
        return v.empty() ? nullptr : &v;
    };
    // the atlas: a tile by its colours
    std::unordered_map<std::string, int> seen;
    std::vector<std::array<uint32_t, 64>> atlas(1);
    auto tile_id = [&](const uint8_t* t, const uint32_t* pal) -> int {
        std::array<uint32_t, 64> c{};
        bool any = false;
        for (int i = 0; i < 64; ++i) { c[static_cast<size_t>(i)] = t[i] ? pal[t[i]] : 0u; any |= t[i] != 0; }
        if (!any) return 0;
        std::string k(reinterpret_cast<const char*>(c.data()), 256);
        auto it = seen.find(k);
        if (it != seen.end()) return it->second;
        if (atlas.size() >= 0xFFFF) return 0;
        const int id = static_cast<int>(atlas.size());
        atlas.push_back(c); seen.emplace(std::move(k), id);
        return id;
    };
    fs::create_directories(lib / "maps");
    std::string js = "{\"game\":\"bf\",\"title\":\"BUU'S FURY\",\"maps\":[";
    int n = 0;
    std::vector<uint8_t> buf;
    for (int i = 0; i < 600; ++i) {
        const uint32_t e = kBfMaps + 56u * static_cast<uint32_t>(i);
        const int z = R.b(e), a = R.b(e + 1);
        if (z == 0 || z > 60) break;
        const uint32_t list = R.w(e + 0x2C);
        if (!R.ok(list)) continue;
        const uint32_t var = R.w(list);
        if (!R.ok(var, 0x50)) continue;
        const int tw = (R.h(var + 8) + 240) / 8, th = (R.h(var + 10) + 160) / 8;
        if (tw <= 0 || th <= 0 || tw > 1024 || th > 1024) continue;
        // the map's tiles: slot -> game-wide number (a delta list) -> its sheet
        std::vector<uint8_t> lst;
        const uint32_t table = R.w(var + 0x4C);
        if (!mapbuild::decode(R.r, R.w(var + 0x48), &lst) || !R.ok(table)) continue;
        std::vector<int> slot_id(1024, 0);
        const int ns = std::min<int>(1024, static_cast<int>(lst.size() / 2));
        int32_t gnum = -1;
        for (int s = 0; s < ns; ++s) {
            gnum += (lst[2 * s] | (lst[2 * s + 1] << 8)) + 1;
            if (gnum < 0) continue;
            const auto* sh = sheet(table, static_cast<uint32_t>(gnum) / 256u);
            const size_t o = static_cast<size_t>(gnum % 256) * 64;
            if (sh && o + 64 <= sh->size()) slot_id[static_cast<size_t>(s)] = tile_id(&(*sh)[o], bpal);
        }
        slot_id[0] = 0;
        // animated tiles (water...): their first picture
        {
            const uint32_t cnt = R.w(var + 0x0C), arr = R.w(var + 0x10);
            for (uint32_t q = 0; q < cnt && q < 32 && R.ok(arr); ++q) {
                const uint32_t dsc = R.w(arr + 4u * q);
                if (!R.ok(dsc, 8)) continue;
                const uint32_t wv = R.w(dsc);
                const int slot = static_cast<int>(wv >> 16), tiles = static_cast<int>((wv >> 8) & 0xFF), frames = static_cast<int>(wv & 0xFF);
                if (slot <= 0 || slot >= 1024 || tiles <= 0 || frames <= 0 || frames > 64) continue;
                const uint32_t p = R.w(dsc + 4);
                if (!R.ok(p, 8)) continue;
                std::vector<uint8_t> px(static_cast<size_t>(tiles) * 64, 0);
                log2rom::decompress(&R.d[p + 4 - 0x08000000u], R.d.size() - (p + 4 - 0x08000000u), 8, px.data(), px.size());
                for (int t = 0; t < tiles && slot + t < 1024; ++t) slot_id[static_cast<size_t>(slot + t)] = tile_id(&px[static_cast<size_t>(t) * 64], bpal);
            }
        }
        // the layers
        const size_t N = static_cast<size_t>(tw) * th;
        std::vector<uint32_t> L[4];
        bool tm[4] = {}; int pri[4] = {};
        for (int k = 0; k < 4; ++k) {
            L[k].assign(N, 0);
            pri[k] = R.b(var + 4 + static_cast<uint32_t>(k)) & 3;
            const uint32_t res = R.w(var + 0x14 + 4u * k);
            if (!R.ok(res, 0x18) || R.w(res) != kBfTilemap) continue;
            tm[k] = true;
            const int cols = R.b(res + 0x14), rows = R.b(res + 0x15);
            const int ox = static_cast<int>(R.w(res + 0x0C) >> 16) * 8, oy = static_cast<int>(R.w(res + 0x10) >> 16) * 8;
            for (int c = 0; c < cols * rows; ++c) {
                const uint32_t d = R.w(res + 0x18 + 4u * c);
                if (!R.ok(d, 8) || !mapbuild::decode(R.r, d, &buf) || buf.size() < 0x800) continue;
                const int cx = (c % cols) * 32 - ox, cy = (c / cols) * 32 - oy;
                for (int y = 0; y < 32; ++y) for (int x = 0; x < 32; ++x) {
                    const int wx = cx + x, wy = cy + y;
                    if (wx < 0 || wy < 0 || wx >= tw || wy >= th) continue;
                    const uint16_t en = static_cast<uint16_t>(buf[(y * 32 + x) * 2] | (buf[(y * 32 + x) * 2 + 1] << 8));
                    const int id = slot_id[en & 0x3FF];
                    if (!id) continue;
                    L[k][static_cast<size_t>(wy) * tw + wx] = static_cast<uint32_t>(id) | (1u << 20) | (1u << 21) | ((en & 0x400) ? 1u << 16 : 0u) | ((en & 0x800) ? 1u << 17 : 0u);
                }
            }
        }
        // a light layer (soft grey, blended by the GBA): left out, as in this game's maps
        auto grey = [&](int k) {
            int tot = 0, g = 0;
            for (uint32_t c : L[k]) {
                if (!c) continue;
                ++tot;
                const auto& t = atlas[c & 0xFFFF];
                bool gr = true; int nn = 0;
                for (uint32_t p : t) { if (!p) continue; ++nn; const int r = p & 255, gg = (p >> 8) & 255, b = (p >> 16) & 255; if (std::abs(r - gg) > 14 || std::abs(gg - b) > 14) { gr = false; break; } }
                g += gr && nn ? 1 : 0;
            }
            return tot >= static_cast<int>(N) / 8 && g * 100 >= tot * 85;
        };
        std::vector<int> ks;
        for (int k = 0; k < 4; ++k) { if (!tm[k] || grey(k)) continue; bool any = false; for (uint32_t c : L[k]) if (c) { any = true; break; } if (any) ks.push_back(k); }
        std::sort(ks.begin(), ks.end(), [&](int x, int y) { return pri[x] != pri[y] ? pri[x] > pri[y] : x > y; });
        std::vector<uint32_t> WL[5];
        for (auto& v : WL) v.assign(N, 0);
        int under = 1, over = 3;
        for (size_t r = 0; r < ks.size(); ++r) {
            const int k = ks[r];
            int wl = 0;
            if (r > 0) { const bool front = pri[k] <= 1 && pri[k] < pri[ks[0]]; wl = front ? std::min(over++, 4) : std::min(under++, 2); }
            for (size_t s = 0; s < N; ++s) if (L[k][s]) WL[wl][s] = L[k][s];
        }
        // walls: the game's own two collision maps
        std::vector<uint8_t> walk(N, 0);
        for (int k = 0; k < 2; ++k) {
            if (!mapbuild::decode(R.r, R.w(var + 0x34 + 4u * k), &buf) || buf.size() < 0x2000) continue;
            for (int y = 0; y < th && y < 256; ++y) for (int x = 0; x < tw && x < 256; ++x)
                if ((buf[static_cast<size_t>(y * 32 + (x >> 3))] >> (x & 7)) & 1) walk[static_cast<size_t>(y) * tw + x] |= static_cast<uint8_t>(1 << k);
        }
        const std::string key = std::to_string(z) + "_" + std::to_string(a);
        std::vector<uint8_t> b = {'L', 'K', 'R', '2', static_cast<uint8_t>(tw), static_cast<uint8_t>(tw >> 8), static_cast<uint8_t>(th), static_cast<uint8_t>(th >> 8)};
        for (auto& v : WL) { const size_t o = b.size(); b.resize(o + N * 4); std::memcpy(&b[o], v.data(), N * 4); }
        b.insert(b.end(), walk.begin(), walk.end());
        { std::ofstream o(lib / "maps" / (key + ".bin"), std::ios::binary); o.write(reinterpret_cast<const char*>(b.data()), static_cast<std::streamsize>(b.size())); }
        const uint32_t arr = R.w(var + 0x30);
        char jb[200];
        std::snprintf(jb, sizeof jb, "%s{\"key\":\"%s\",\"zone\":%d,\"area\":%d,\"tw\":%d,\"th\":%d,\"arrival\":[%u,%u]}", n ? "," : "", key.c_str(), z, a, tw, th, arr & 0xFFFF, arr >> 16);
        js += jb;
        ++n;
    }
    // the atlas
    const int cols = 64, rows = static_cast<int>((atlas.size() + cols - 1) / cols);
    std::vector<uint8_t> img(static_cast<size_t>(cols * 8) * rows * 8 * 4, 0);
    for (size_t id = 1; id < atlas.size(); ++id) {
        const int cx = static_cast<int>(id % cols) * 8, cy = static_cast<int>(id / cols) * 8;
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) std::memcpy(&img[(static_cast<size_t>(cy + y) * cols * 8 + cx + x) * 4], &atlas[id][static_cast<size_t>(y * 8 + x)], 4);
    }
    romcat::save_png_rgba((lib / "tiles.png").string(), img, cols * 8, rows * 8);
    js += "],\"tiles\":" + std::to_string(atlas.size()) + "}";
    write_text(lib / "maps.json", js);
    return n;
}

// ================================================================ The Legacy of Goku (its own engine): the characters
static int l1_sprites(const LR& R, const fs::path& out, const fs::path& lib) {
    auto rec_ok = [&](uint32_t a) { const uint32_t pal = R.w(a), an = R.w(a + 4); return R.ok(pal, 32) && R.h(pal) == 0x7C1Fu && R.ok(an, 0x110) && R.ok(R.w(an), 16); };
    uint32_t best = 0; int bn = 0;
    const uint32_t end = 0x08000000u + static_cast<uint32_t>(R.d.size()) - 0x2C;
    for (uint32_t a = 0x08000000u; a < end; a += 4) {
        if (!rec_ok(a) || rec_ok(a - 0x2C)) continue;
        int n = 0; while (a + 0x2Cu * static_cast<uint32_t>(n) < end && rec_ok(a + 0x2Cu * static_cast<uint32_t>(n))) ++n;
        if (n > bn) { bn = n; best = a; }
    }
    if (bn < 20) return 0;
    std::fprintf(stderr, "[library] LoG1: %d characters at %08X\n", bn, best);
    struct St { int x, y, w, h, flags; uint32_t gfx; };
    auto strip = [&](uint32_t a, St* s) {
        if (!R.ok(a, 16)) return false;
        s->x = static_cast<int16_t>(R.h(a)); s->y = static_cast<int16_t>(R.h(a + 2)); s->w = R.h(a + 4); s->h = R.h(a + 6); s->flags = R.b(a + 9); s->gfx = R.w(a + 12);
        auto okd = [](int v) { return v == 8 || v == 16 || v == 32 || v == 64; };
        return okd(s->w) && okd(s->h) && R.ok(s->gfx, static_cast<size_t>(s->w * s->h / 2));
    };
    // every strip's pictures start somewhere: a strip has as many frames as fit before the next one starts
    std::set<uint32_t> starts;
    for (int r = 0; r < bn; ++r) {
        const uint32_t an = R.w(best + 0x2Cu * static_cast<uint32_t>(r) + 4);
        for (int k = 0; k < 17 * 4; ++k) { St s; if (strip(R.w(an + 4u * k), &s)) starts.insert(s.gfx); }
    }
    static const int kDirFrom[4] = {0, 1, 3, 2};   // down, up, left, right <- LoG1's down, up, (mirrored) right, left
    fs::create_directories(out);
    std::string js = "{\"game\":\"log1\",\"sets\":[";
    int n = 0;
    for (int r = 0; r < bn; ++r) {
        const uint32_t ra = best + 0x2Cu * static_cast<uint32_t>(r), pa = R.w(ra), an = R.w(ra + 4);
        uint32_t pal[16];
        for (int c = 0; c < 16; ++c) pal[c] = c ? rgba555(R.h(pa + 2u * c)) : 0u;
        std::vector<std::vector<LFrame>> slots;
        int frames_all = 0;
        for (int A = 0; A < 17; ++A) for (int d = 0; d < 4; ++d) {
            std::vector<LFrame> fr;
            St s;
            if (strip(R.w(an + 16u * A + 4u * kDirFrom[d]), &s)) {
                const uint32_t nb = static_cast<uint32_t>(s.w * s.h / 2);
                auto nx = starts.upper_bound(s.gfx);
                int nf = nx == starts.end() ? 1 : static_cast<int>((*nx - s.gfx) / nb);
                nf = std::max(1, std::min(nf, 8));
                for (int f = 0; f < nf; ++f) {
                    const uint32_t g = s.gfx + nb * static_cast<uint32_t>(f);
                    if (!R.ok(g, nb)) break;
                    LFrame F; F.w = s.w; F.h = s.h; F.ox = s.x; F.oy = s.y; F.px.assign(static_cast<size_t>(s.w * s.h), 0u);
                    const int tw = s.w / 8;
                    const bool mir = (s.flags & 8) != 0;
                    for (int y = 0; y < s.h; ++y) for (int x = 0; x < s.w; ++x) {
                        const int t = (y / 8) * tw + x / 8, b = R.b(g + static_cast<uint32_t>(t * 32 + (y & 7) * 4 + (x & 7) / 2));
                        const int v = (x & 1) ? (b >> 4) : (b & 15);
                        if (!v) continue;
                        const int X = mir ? s.w - 1 - x : x;
                        F.px[static_cast<size_t>(y * s.w + X)] = pal[v];
                    }
                    fr.push_back(std::move(F));
                    ++frames_all;
                }
            }
            slots.push_back(std::move(fr));
        }
        if (!frames_all) continue;
        // trailing animations it does not have
        while (!slots.empty() && slots.back().empty()) slots.pop_back();
        while (slots.size() % 4) slots.push_back({});
        const int id = 2000 + r;
        write_set(out, id, slots);
        char b[96]; std::snprintf(b, sizeof b, "%s{\"id\":%d,\"slots\":%zu,\"record\":%d}", n ? "," : "", id, slots.size(), r);
        js += b;
        ++n;
    }
    write_text(lib / "sets.json", js + "]}");
    return n;
}

// ================================================================ The Legacy of Goku: its maps (its own engine)
// A map: a 0x34-byte record {s16 screens w, h, tiles w, h; walk bits, 2 more bit maps, animated tiles, the screens'
// tile set numbers, the tile sets, 3 layers (a table of screen pointers each: 30 x 20 u16 entries), palette, tiles}.
// Graphics are packed with the BIOS codecs, chained (bit 4 Huffman, 3 LZ77, 2 RL, 1 diff16, 0 diff8).
static std::vector<uint8_t> gba_huff(const LR& R, uint32_t a) {
    std::vector<uint8_t> out;
    const uint32_t h = R.w(a); const int bits = h & 15; const uint32_t n = h >> 8;
    if ((h & 0xF0) != 0x20 || n > 0x100000) return out;
    const uint32_t troot = a + 5; uint32_t p = a + 4 + (R.b(a + 4) + 1u) * 2u;
    uint32_t node = troot; uint32_t acc = 0; int nacc = 0;
    while (out.size() < n && R.ok(p)) {
        uint32_t word = R.w(p); p += 4;
        for (int i = 0; i < 32 && out.size() < n; ++i) {
            const int bit = (word >> 31) & 1; word <<= 1;
            const uint8_t v = R.b(node);
            const uint32_t child = (node & ~1u) + (v & 0x3Fu) * 2u + 2u + static_cast<uint32_t>(bit);
            if (v & (bit ? 0x40 : 0x80)) {
                acc |= static_cast<uint32_t>(R.b(child)) << nacc; nacc += bits; node = troot;
                if (nacc >= 8) { out.push_back(static_cast<uint8_t>(acc)); acc >>= 8; nacc -= 8; }
            } else node = child;
        }
    }
    return out;
}
static std::vector<uint8_t> gba_lz(const std::vector<uint8_t>& d) {
    std::vector<uint8_t> out;
    if (d.size() < 4 || (d[0] & 0xF0) != 0x10) return out;
    const uint32_t n = d[1] | d[2] << 8 | d[3] << 16; size_t p = 4;
    while (out.size() < n && p < d.size()) {
        uint8_t f = d[p++];
        for (int b = 0; b < 8 && out.size() < n; ++b, f <<= 1) {
            if (f & 0x80) {
                if (p + 1 >= d.size()) return out;
                const int ln = (d[p] >> 4) + 3; const size_t disp = (static_cast<size_t>(d[p] & 15) << 8 | d[p + 1]) + 1; p += 2;
                for (int k = 0; k < ln; ++k) out.push_back(disp <= out.size() ? out[out.size() - disp] : 0);
            } else if (p < d.size()) out.push_back(d[p++]);
        }
    }
    out.resize(n); return out;
}
static std::vector<uint8_t> gba_rl(const std::vector<uint8_t>& d) {
    std::vector<uint8_t> out;
    if (d.size() < 4 || (d[0] & 0xF0) != 0x30) return out;
    const uint32_t n = d[1] | d[2] << 8 | d[3] << 16; size_t p = 4;
    while (out.size() < n && p < d.size()) {
        const uint8_t f = d[p++];
        if (f & 0x80) { const int ln = (f & 0x7F) + 3; const uint8_t v = p < d.size() ? d[p] : 0; ++p; out.insert(out.end(), static_cast<size_t>(ln), v); }
        else { const int ln = (f & 0x7F) + 1; for (int k = 0; k < ln && p < d.size(); ++k) out.push_back(d[p++]); }
    }
    out.resize(n); return out;
}
static std::vector<uint8_t> l1_unpack(const LR& R, uint32_t ptr, int kind) {
    std::vector<uint8_t> d;
    if (!R.ok(ptr, 8)) return d;
    bool raw = true;
    if (kind & 0x10) { d = gba_huff(R, ptr); raw = false; }
    auto src = [&]() -> std::vector<uint8_t> {
        if (!raw) return d;
        const uint32_t n = R.w(ptr) >> 8; std::vector<uint8_t> v(R.d.begin() + (ptr - 0x08000000u), R.d.begin() + std::min<size_t>(R.d.size(), ptr - 0x08000000u + 4 + n + 0x10000)); return v; };
    if (kind & 0x08) { d = gba_lz(src()); raw = false; }
    if (kind & 0x04) { d = gba_rl(src()); raw = false; }
    if (kind & 0x03) {
        std::vector<uint8_t> s2 = src();
        if (s2.size() < 4) return {};
        const uint32_t n = s2[1] | s2[2] << 8 | s2[3] << 16;
        std::vector<uint8_t> o(s2.begin() + 4, s2.begin() + 4 + std::min<size_t>(n, s2.size() - 4));
        if (kind & 0x02) for (size_t i = 2; i + 1 < o.size(); i += 2) { const uint16_t v = static_cast<uint16_t>((o[i] | o[i + 1] << 8) + (o[i - 2] | o[i - 1] << 8)); o[i] = static_cast<uint8_t>(v); o[i + 1] = static_cast<uint8_t>(v >> 8); }
        else for (size_t i = 1; i < o.size(); ++i) o[i] = static_cast<uint8_t>(o[i] + o[i - 1]);
        d = o; raw = false;
    }
    return raw ? std::vector<uint8_t>() : d;
}
static int l1_maps(const LR& R, const fs::path& lib) {
    const uint32_t N = static_cast<uint32_t>(R.d.size());
    auto rec_ok = [&](uint32_t a) {
        const int sw = static_cast<int16_t>(R.h(a)), sh = static_cast<int16_t>(R.h(a + 2)), tw = static_cast<int16_t>(R.h(a + 4)), th = static_cast<int16_t>(R.h(a + 6));
        if (sw < 1 || sh < 1 || sw > 40 || sh > 40 || tw != sw * 30 || th != sh * 20) return false;
        for (uint32_t k : {0x08u, 0x20u, 0x24u, 0x28u, 0x2Cu, 0x30u}) if (!R.ok(R.w(a + k))) return false;
        for (uint32_t k : {0x18u, 0x1Cu}) if (R.w(a + k) && !R.ok(R.w(a + k))) return false;
        return R.h(R.w(a + 0x2C)) == 0x7C1Fu;
    };
    uint32_t best = 0; int bn = 0;
    for (uint32_t a = 0x08000000u; a + 0x34 < 0x08000000u + N; a += 4) {
        if (!rec_ok(a) || rec_ok(a - 0x34)) continue;
        int n = 0; while (rec_ok(a + 0x34u * static_cast<uint32_t>(n))) ++n;
        if (n > bn) { bn = n; best = a; }
    }
    if (bn < 5) { std::fprintf(stderr, "[library] LoG1: map table not found\n"); return 0; }
    // the tiles every map shares (the first ones) and the first 16 colours: {palette, tiles, codec}
    std::vector<uint8_t> common; uint32_t basepal = 0;
    for (uint32_t a = 0x08000000u; a + 12 < 0x08000000u + N && common.empty(); a += 4) {
        const uint32_t pp = R.w(a), tp = R.w(a + 4), k = R.w(a + 8);
        if (k != 0x18 || !R.ok(pp, 32) || !R.ok(tp, 8) || R.h(pp) != 0x7C1Fu || (R.b(tp) & 0xF0) != 0x20) continue;
        std::vector<uint8_t> t = l1_unpack(R, tp, 0x18);
        if (t.size() >= 0x92 * 64 && t.size() <= 0x100 * 64) { common = t; basepal = pp; }
    }
    std::fprintf(stderr, "[library] LoG1: %d maps at %08X, shared tiles %zu\n", bn, best, common.size());
    std::unordered_map<std::string, int> seen;
    std::vector<std::array<uint32_t, 64>> atlas(1);
    auto tile_id = [&](const uint8_t* t, const uint32_t* pal) -> int {
        std::array<uint32_t, 64> c{}; bool any = false;
        for (int i = 0; i < 64; ++i) { c[static_cast<size_t>(i)] = t[i] ? pal[t[i]] : 0u; any |= t[i] != 0; }
        if (!any) return 0;
        std::string k(reinterpret_cast<const char*>(c.data()), 256);
        auto it = seen.find(k); if (it != seen.end()) return it->second;
        if (atlas.size() >= 0xFFFF) return 0;
        const int id = static_cast<int>(atlas.size()); atlas.push_back(c); seen.emplace(std::move(k), id); return id;
    };
    fs::create_directories(lib / "maps");
    std::string js = "{\"game\":\"log1\",\"title\":\"LEGACY OF GOKU\",\"maps\":[";
    std::map<std::pair<uint32_t, int>, std::vector<uint8_t>> cache;
    auto unpack = [&](uint32_t entry) -> const std::vector<uint8_t>& {
        const auto key = std::make_pair(R.w(entry), static_cast<int>(R.b(entry + 4)));
        auto it = cache.find(key); if (it != cache.end()) return it->second;
        return cache[key] = l1_unpack(R, key.first, key.second);
    };
    int n = 0;
    for (int i = 0; i < bn; ++i) {
        const uint32_t a = best + 0x34u * static_cast<uint32_t>(i);
        const int sw = R.h(a), sh = R.h(a + 2), tw = R.h(a + 4), th = R.h(a + 6);
        const uint32_t walkp = R.w(a + 8), regmap = R.w(a + 0x18), regs = R.w(a + 0x1C), palp = R.w(a + 0x2C), t2 = R.w(a + 0x30);
        uint32_t pal[256];
        for (int c = 0; c < 256; ++c) pal[c] = rgba555(R.h((c < 16 && basepal ? basepal : palp) + 2u * static_cast<uint32_t>(c)));
        const size_t NN = static_cast<size_t>(tw) * th;
        std::vector<uint32_t> WL[5];
        for (auto& v : WL) v.assign(NN, 0);
        std::map<int, std::vector<int>> slot_ids;     // region -> tile number -> atlas id
        auto ids_for = [&](int region) -> const std::vector<int>& {
            auto it = slot_ids.find(region); if (it != slot_ids.end()) return it->second;
            std::vector<uint8_t> vr(0x380 * 64, 0);
            std::memcpy(vr.data(), common.data(), std::min(common.size(), vr.size()));
            const auto& b2 = unpack(t2); std::memcpy(&vr[0x92 * 64], b2.data(), std::min(b2.size(), vr.size() - 0x92 * 64));
            if (region > 0 && regs) { const auto& b3 = unpack(R.w(regs + 4u * static_cast<uint32_t>(region - 1))); std::memcpy(&vr[0x15A * 64], b3.data(), std::min(b3.size(), vr.size() - 0x15A * 64)); }
            std::vector<int> ids(0x400, 0);
            for (int t = 1; t < 0x380; ++t) ids[static_cast<size_t>(t)] = tile_id(&vr[static_cast<size_t>(t) * 64], pal);
            return slot_ids[region] = ids;
        };
        static const int kLayerTo[3] = {3, 1, 0};     // BG1 (over the heroes), BG2, BG3 (the ground)
        for (int sy = 0; sy < sh; ++sy) for (int sx = 0; sx < sw; ++sx) {
            const auto& ids = ids_for(regmap ? R.b(regmap + static_cast<uint32_t>(sy * sw + sx)) : 0);
            for (int k = 0; k < 3; ++k) {
                const uint32_t scr = R.w(R.w(a + 0x20 + 4u * k) + 4u * static_cast<uint32_t>(sy * sw + sx));
                if (!R.ok(scr, 1200)) continue;
                for (int y = 0; y < 20; ++y) for (int x = 0; x < 30; ++x) {
                    const uint16_t e = R.h(scr + 2u * static_cast<uint32_t>(y * 30 + x));
                    const int id = ids[e & 0x3FF];
                    if (!id) continue;
                    WL[kLayerTo[k]][static_cast<size_t>(sy * 20 + y) * tw + sx * 30 + x] = static_cast<uint32_t>(id) | (1u << 20) | (2u << 21) | ((e & 0x400) ? 1u << 16 : 0u) | ((e & 0x800) ? 1u << 17 : 0u);
                }
            }
        }
        std::vector<uint8_t> walk(NN, 0);
        for (size_t k = 0; k < NN; ++k) walk[k] = (R.b(walkp + static_cast<uint32_t>(k >> 3)) >> (k & 7)) & 1;
        const std::string key = "0_" + std::to_string(i);
        std::vector<uint8_t> b = {'L', 'K', 'R', '2', static_cast<uint8_t>(tw), static_cast<uint8_t>(tw >> 8), static_cast<uint8_t>(th), static_cast<uint8_t>(th >> 8)};
        for (auto& v : WL) { const size_t o = b.size(); b.resize(o + NN * 4); std::memcpy(&b[o], v.data(), NN * 4); }
        b.insert(b.end(), walk.begin(), walk.end());
        { std::ofstream o(lib / "maps" / (key + ".bin"), std::ios::binary); o.write(reinterpret_cast<const char*>(b.data()), static_cast<std::streamsize>(b.size())); }
        char jb[200];
        std::snprintf(jb, sizeof jb, "%s{\"key\":\"%s\",\"zone\":0,\"area\":%d,\"tw\":%d,\"th\":%d}", n ? "," : "", key.c_str(), i, tw, th);
        js += jb; ++n;
    }
    const int cols = 64, rows = static_cast<int>((atlas.size() + cols - 1) / cols);
    std::vector<uint8_t> img(static_cast<size_t>(cols * 8) * rows * 8 * 4, 0);
    for (size_t id = 1; id < atlas.size(); ++id) {
        const int cx = static_cast<int>(id % cols) * 8, cy = static_cast<int>(id / cols) * 8;
        for (int y = 0; y < 8; ++y) for (int x = 0; x < 8; ++x) std::memcpy(&img[(static_cast<size_t>(cy + y) * cols * 8 + cx + x) * 4], &atlas[id][static_cast<size_t>(y * 8 + x)], 4);
    }
    romcat::save_png_rgba((lib / "tiles.png").string(), img, cols * 8, rows * 8);
    js += "],\"tiles\":" + std::to_string(atlas.size()) + "}";
    write_text(lib / "maps.json", js);
    return n;
}

static int run(const char* rom_path, const fs::path& outdir) {
    LR R;
    {
        std::ifstream f(rom_path, std::ios::binary);
        R.d.assign((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    }
    if (R.d.size() < 0x200000) { std::fprintf(stderr, "[library] cannot read %s\n", rom_path); return 1; }
    R.r = mapbuild::Rom{R.d.data(), R.d.size()};
    const std::string code(reinterpret_cast<const char*>(&R.d[0xAC]), 4);
    if (code == "BG3E") {
        const fs::path lib = outdir / "lib" / "bf";
        fs::create_directories(lib);
        const int m = bf_maps(R, lib);
        const int s = bf_sprites(R, outdir / "sprites", lib);
        write_text(lib / "done.txt", "1");
        std::fprintf(stderr, "[library] Buu's Fury: %d maps, %d sprite sets\n", m, s);
        return 0;
    }
    if (code.substr(0, 3) == "ALG") {
        const fs::path lib = outdir / "lib" / "log1";
        fs::create_directories(lib);
        const int s = l1_sprites(R, outdir / "sprites", lib);
        const int m = l1_maps(R, lib);
        write_text(lib / "done.txt", "2");
        std::fprintf(stderr, "[library] Legacy of Goku: %d characters, %d maps\n", s, m);
        return s ? 0 : 1;
    }
    std::fprintf(stderr, "[library] %s is not Buu's Fury or The Legacy of Goku (%s)\n", rom_path, code.c_str());
    return 1;
}
}  // namespace libx
