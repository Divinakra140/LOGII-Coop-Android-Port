// rom_sprites.h - read Legacy of Goku II (USA) character sprites straight from
// the player's own ROM (for the start menu's character select). Nothing from
// the game is bundled; this decodes the cartridge data at run time.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace log2rom {

struct Image {
    int w = 0, h = 0;
    std::vector<std::uint32_t> rgba;   // 0xAABBGGRR (little-endian RGBA bytes)
};

class Sprites {
public:
    bool load(const std::string& rom_path);
    bool ok() const { return !rom_.empty(); }
    // Frame `frame` of animation `anim` facing `dir` (0 down, 1 up, 2 right,
    // 3 left) of sprite set `set`. Returns false if it does not exist.
    bool frame(int set, int anim, int dir, int frame, Image* out) const;
    int frame_count(int set, int anim, int dir) const;

private:
    std::uint32_t u32(std::uint32_t addr) const;
    bool rom_ptr(std::uint32_t v) const;
    std::vector<std::uint8_t> rom_;
    std::uint32_t pal_[256] = {};
};

// The game's graphics decompressor (ported from the ARM routine it copies to
// IWRAM 0x03000000). `src` points just past the 8-byte gfx header.
void decompress(const std::uint8_t* src, std::size_t src_len, std::uint32_t lit_bits,
                std::uint8_t* dst, std::size_t dst_len);

}  // namespace log2rom
