#pragma once
// rom_tiles - every map's tile graphics, read straight from the cartridge.
//
// All map graphics of the game live in one table of compressed 16 KB sheets
// (256 tiles of 8x8, 256 colours each) and all maps share ONE background
// palette. A map picks its tiles with a list of sheet tile numbers (variant
// +0x48, delta coded; variant +0x4C = the sheet table): VRAM tile slot i of
// that map = list entry i. A handful of high slots hold animated tiles that
// the game copies in while it runs (not in the sheets).
//
// Tile ids: equal id = the tile looks exactly the same (same 64 pixels), in
// any map. Nothing is shipped: everything comes from the player's game.
#include <cstdint>
#include <string>
#include <vector>
#include "map_builder.h"

namespace romtiles {

void init(const mapbuild::Rom& rom);            // once (any thread); cheap to call again

struct MapRef { int z, a; uint32_t entry, var; };
const std::vector<MapRef>& maps();              // every map of the map table with a tile list

// 1024 ids for a map's tile slots (0 = empty slot); nullptr if the map has no list
const uint16_t* ids(int z, int a);
int slot_count(int z, int a);                   // how many slots come from the sheets
const uint8_t* global_tile(uint32_t gnum);       // a game-wide tile number's pixels (nullptr: empty)
uint16_t global_id(uint32_t gnum);               // a game-wide tile number's look id (0: empty)
int global_count();                             // game-wide tile numbers (sheets x 256)

const std::vector<uint32_t>& id_globals();      // id -> game-wide tile number (sheet * 256 + tile) - for a floor's own tile list
const uint8_t* tile(uint16_t id);               // 64 palette indices (0 = transparent), nullptr for animated / unknown
const uint8_t* map_tile(int z, int a, int slot); // same, by map slot
void palette_rgb(uint8_t out[256 * 3]);         // the shared background palette

std::string place_name(int z, int a);           // "Northern Mountains", ...
std::string game_string(int index);             // the game's own string table

}  // namespace romtiles
