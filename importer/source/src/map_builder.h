#pragma once
// map_builder: new floors grown from the game's own maps (tile bank + WFC).
#include <cstdint>
#include <cstddef>
#include <vector>

namespace mapbuild {

struct Rom {                       // read-only view of the cartridge (0x08000000-based)
    const uint8_t* p = nullptr; size_t n = 0;
    size_t orig = 0;               // (in the game: the cartridge's own size - map data past it is a new floor, not a source)
    bool made(uint32_t a) const { return orig && a >= 0x08000000u && a - 0x08000000u >= orig; }
    bool ok(uint32_t a, size_t k = 1) const { return a >= 0x08000000u && a - 0x08000000u + k <= n; }
    uint8_t r8(uint32_t a) const { return ok(a) ? p[a - 0x08000000u] : 0; }
    uint16_t r16(uint32_t a) const { return static_cast<uint16_t>(r8(a) | (r8(a + 1) << 8)); }
    uint32_t r32(uint32_t a) const { return r16(a) | (static_cast<uint32_t>(r16(a + 2)) << 16); }
};

bool decode(const Rom& rom, uint32_t desc, std::vector<uint8_t>* out);

struct Rect { uint16_t x0, y0, x1, y1; };
struct SrcMap {
    int z = 0, a = 0, tw = 0, th = 0;
    std::vector<uint16_t> L[4];     // world tile maps, tw*th
    uint8_t pri[4] = {0, 0, 0, 0};  // layer priorities (3 = drawn first / at the back)
    bool tilemap[4] = {false, false, false, false};   // layer k is an ordinary tile map (not missing / an effect layer)
    std::vector<uint8_t> wa, wb;    // walk bits (collision blobs A / B), tw*th
    std::vector<Rect> exits;
};
bool load_src(const Rom& rom, int z, int a, SrcMap* m);

// bank ids: per map, 1024 u16 = global id of each tile index by its look
struct BankMap { int z, a; const uint16_t* ids; };

struct Options {
    int tw = 56, th = 40;          // size in tiles
    int in_side = 3, out_side = 2;  // 0 left, 1 right, 2 top, 3 bottom (-1 = any)
    int side_side = -1;             // a third exit (a way to a side place) on this side; -1 none
    bool dead_end = false;          // only the way in is an exit (a side place)
    int rooms = 3;
    int stamps = -1;                // whole buildings / features set down (-1 = the default, 2)
    int foreign = 0;                // things lifted whole from any map of the game set down (needs id_global, tile_pixels, palette)
    bool keep_clearing = false;     // the first try keeps a clearing for one big thing (costs a try now and then: off in the game)
    int layout = 0;                 // 0 clearings + ways, 1 an open field with islands, 2 a river across (fords where the way crosses), 3 a lake
    unsigned long long work_max = 0; // give up after this much work (0 = default; same on every PC)
    int threads = 1;
    void (*thread_init)() = nullptr;  // called first on each extra thread (e.g. its priority)
    bool shrink_early = false;     // only the first two tries at full size, then smaller
    int accept_bad = 0;
    bool strict_visual = false;    // reject invalid tile joins, including after decoration
    int push = 16;                 // bad pairs the last mending pass takes on one by one            // a floor with this many seams (pairs no map has) left still counts               // tries built at once (the result does not depend on it)
    // Mixing worlds: the floor holds pieces of several regions (region 0 at the
    // way in, the last one at the way on), each with its own tiles; the floor
    // gets a tile list of its own (game-wide tile numbers, see rom_tiles.h).
    std::vector<std::vector<std::pair<int, int>>> regions;
    const std::vector<uint32_t>* id_global = nullptr;   // tile id -> game-wide tile number
    int region_cells = 4000;                             // library size per region
    // tile pictures (for joining regions by how their edges look): id -> 64
    // palette indices (0 = see-through), and the 256-colour palette (RGB)
    const uint8_t* (*tile_pixels)(uint16_t id) = nullptr;
    const uint8_t* palette = nullptr;
};
struct Out {
    int tw = 0, th = 0;
    std::vector<uint16_t> L[4];
    std::vector<uint8_t> wa, wb;
    std::vector<Rect> exits;       // [0] = way in, [1] = way on
    int exit_side[3] = {3, 2, -1}; // 0 left, 1 right, 2 top, 3 bottom (exit 2: the side way, when there is one)
    uint16_t spawn_x = 0, spawn_y = 0;
    int cells = 0, attempts = 0, bad_pairs = 0, seam_bad = 0;
    bool connected = false;
    unsigned long long work = 0;   // work units used
    int loose = 0;                 // pairs kept that only fit layer by layer
    int landmarks = 0;             // real features laid down whole (most of their cells kept)
    int foreign = 0;               // things from other maps set down (the floor then has a tile list of its own)
    int keep_x = -1, keep_y = 0, keep_w = 0, keep_h = 0;   // the clearing kept for one of them (-1: none)
    std::vector<uint32_t> tile_list;  // mixed floor: slot -> game-wide tile number (empty = the area's own tiles)
    std::vector<int8_t> region;       // mixed floor: planned region of each cell
    std::vector<int8_t> mask;      // the room plan (debug)
};
// base = the area whose graphics the new floor uses; sources = maps it may learn from
bool build(const Rom& rom, int bz, int ba, const std::vector<BankMap>& bank,
           const std::vector<std::pair<int, int>>& sources, uint32_t seed,
           const Options& opt, Out* out);

bool write_gen(const char* path, int z, int a, const Out& out);

}  // namespace mapbuild
