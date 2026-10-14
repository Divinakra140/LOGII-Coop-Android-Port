// rom_tiles.cpp - see rom_tiles.h
#include "rom_tiles.h"
#include <array>
#include <cstring>
#include <map>
#include <mutex>
#include <unordered_map>

namespace romtiles {
namespace {
constexpr uint32_t kMapTable = 0x08409368u;   // 56-byte map entries
constexpr uint32_t kPalette = 0x081da4c8u;    // the shared background palette (256 x BGR555)
constexpr uint32_t kStrings = 0x080e2840u;    // the game's string table (pointers)

struct State {
    mapbuild::Rom rom;
    std::vector<MapRef> maps;
    uint32_t sheet_table = 0;
    std::vector<uint16_t> canon;                 // global tile number -> id (0 = empty)
    std::vector<std::array<uint8_t, 64>> pix;    // id -> pixels (id 0 unused)
    std::vector<uint32_t> first;                 // id -> first game-wide tile number with that look
    std::map<std::pair<int, int>, std::vector<uint16_t>> ids;
    std::map<std::pair<int, int>, int> slots;
    std::map<std::pair<int, int>, std::vector<std::array<uint8_t, 64>>> slot_pix;
};
State* g = nullptr;
std::once_flag g_once;
std::mutex g_m;

struct TileKey {
    std::array<uint8_t, 64> b;
    bool operator==(const TileKey& o) const { return b == o.b; }
};
struct TileHash { size_t operator()(const TileKey& k) const { uint64_t h = 1469598103934665603ull; for (uint8_t c : k.b) h = (h ^ c) * 1099511628211ull; return static_cast<size_t>(h); } };

void load(const mapbuild::Rom& rom) {
    g = new State;
    g->rom = rom;
    for (int i = 0; i < 600; ++i) {
        const uint32_t e = kMapTable + 56u * static_cast<uint32_t>(i);
        const int z = rom.r8(e), a = rom.r8(e + 1);
        if (z == 0 || z > 40) break;
        const uint32_t list = rom.r32(e + 0x2C);
        if (!rom.ok(list, 4)) continue;
        const uint32_t var = rom.r32(list);
        if (rom.made(var) || !rom.ok(var, 0x50) || !rom.ok(rom.r32(var + 0x48), 8) || !rom.ok(rom.r32(var + 0x4C), 4)) continue;
        g->maps.push_back({z, a, e, var});
        if (!g->sheet_table) g->sheet_table = rom.r32(var + 0x4C);
    }
    // every sheet, every tile: one id per distinct look (in sheet order: the same ids every run)
    std::unordered_map<TileKey, uint16_t, TileHash> seen;
    g->pix.push_back({});
    g->first.push_back(0);
    std::vector<uint8_t> buf;
    for (int k = 0; k < 256 && g->sheet_table; ++k) {
        const uint32_t d = rom.r32(g->sheet_table + 4u * static_cast<uint32_t>(k));
        if (!rom.ok(d, 8) || rom.r32(d) > 8) break;
        if (!mapbuild::decode(rom, d, &buf) || buf.size() < 64) break;
        const size_t n = buf.size() / 64;
        g->canon.resize(static_cast<size_t>(k) * 256, 0);
        for (size_t j = 0; j < 256; ++j) {
            if (j >= n) { g->canon.push_back(0); continue; }
            TileKey t; std::memcpy(t.b.data(), &buf[j * 64], 64);
            bool any = false; for (uint8_t c : t.b) any |= c != 0;
            if (!any) { g->canon.push_back(0); continue; }
            auto it = seen.find(t);
            if (it == seen.end()) {
                if (g->pix.size() >= 0xC000) { g->canon.push_back(0); continue; }
                it = seen.emplace(t, static_cast<uint16_t>(g->pix.size())).first;
                g->pix.push_back(t.b);
                g->first.push_back(static_cast<uint32_t>(k) * 256u + static_cast<uint32_t>(j));
            }
            g->canon.push_back(it->second);
        }
    }
}
const std::vector<uint16_t>* map_ids(int z, int a) {
    std::lock_guard<std::mutex> lk(g_m);
    auto key = std::make_pair(z, a);
    auto it = g->ids.find(key);
    if (it != g->ids.end()) return it->second.empty() ? nullptr : &it->second;
    std::vector<uint16_t>& v = g->ids[key];
    const MapRef* m = nullptr;
    for (const auto& r : g->maps) if (r.z == z && r.a == a) { m = &r; break; }
    if (!m) return nullptr;
    std::vector<uint8_t> lst;
    if (!mapbuild::decode(g->rom, g->rom.r32(m->var + 0x48), &lst)) return nullptr;
    v.assign(1024, 0);
    const int n = std::min<int>(1024, static_cast<int>(lst.size() / 2));
    int32_t gnum = -1;
    for (int i = 0; i < n; ++i) {
        gnum += (lst[2 * i] | (lst[2 * i + 1] << 8)) + 1;
        if (gnum >= 0 && static_cast<size_t>(gnum) < g->canon.size()) v[static_cast<size_t>(i)] = g->canon[static_cast<size_t>(gnum)];
    }
    v[0] = 0;
    // slots past the list: animated tiles the game copies in while it runs -
    // taken as the same tile within a zone (the zone's own animations), and
    // only the slots this map really uses (only those are animated here: a
    // borrowed slot the map does not animate showed as a black square)
    {
        mapbuild::SrcMap sm;
        if (mapbuild::load_src(g->rom, z, a, &sm))
            for (int k = 0; k < 4; ++k) for (uint16_t e : sm.L[k]) {
                const int t = e & 0x3FF;
                if (t >= n) v[static_cast<size_t>(t)] = static_cast<uint16_t>(0xC000 + ((z & 15) << 10) + t);
            }
    }
    g->slots[key] = n;
    return &v;
}
}  // namespace

void init(const mapbuild::Rom& rom) { std::call_once(g_once, [&] { load(rom); }); }
const std::vector<MapRef>& maps() { static const std::vector<MapRef> none; return g ? g->maps : none; }
const uint16_t* ids(int z, int a) { if (!g) return nullptr; const auto* v = map_ids(z, a); return v ? v->data() : nullptr; }
int slot_count(int z, int a) { if (!g || !map_ids(z, a)) return 0; std::lock_guard<std::mutex> lk(g_m); return g->slots[{z, a}]; }
uint16_t global_id(uint32_t gnum) { return (g && gnum < g->canon.size()) ? g->canon[gnum] : 0; }
int global_count() { return g ? static_cast<int>(g->canon.size()) : 0; }
const std::vector<uint32_t>& id_globals() { static const std::vector<uint32_t> none; return g ? g->first : none; }
const uint8_t* tile(uint16_t id) { return (g && id > 0 && id < g->pix.size()) ? g->pix[id].data() : nullptr; }
const uint8_t* global_tile(uint32_t gnum) { return (g && gnum < g->canon.size()) ? tile(g->canon[gnum]) : nullptr; }
const uint8_t* map_tile(int z, int a, int slot) {
    const uint16_t* v = ids(z, a);
    return (v && slot >= 0 && slot < 1024) ? tile(v[slot]) : nullptr;
}
void palette_rgb(uint8_t out[256 * 3]) {
    for (int i = 0; i < 256; ++i) {
        const uint16_t c = g ? g->rom.r16(kPalette + 2u * static_cast<uint32_t>(i)) : 0;
        out[i * 3] = static_cast<uint8_t>((c & 31) << 3); out[i * 3 + 1] = static_cast<uint8_t>(((c >> 5) & 31) << 3); out[i * 3 + 2] = static_cast<uint8_t>(((c >> 10) & 31) << 3);
    }
}
std::string game_string(int index) {
    if (!g || index < 0 || index > 4000) return {};
    const uint32_t p = g->rom.r32(kStrings + 4u * static_cast<uint32_t>(index));
    std::string s;
    for (uint32_t q = p; g->rom.ok(q) && s.size() < 200; ++q) { const char c = static_cast<char>(g->rom.r8(q)); if (!c) break; s.push_back(c); }
    return s;
}
std::string place_name(int z, int a) {
    if (!g) return {};
    for (const auto& r : g->maps) if (r.z == z && r.a == a) { const int n = g->rom.r16(r.entry + 0x0C); return n > 0 ? game_string(n) : std::string(); }
    return {};
}
}  // namespace romtiles
