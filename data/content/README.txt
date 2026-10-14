MAKING THE GAME YOUR OWN - content/*.json
=========================================

Everything below is plain text. Open a file in Notepad, change it, save, start the game.
The files in this "content" folder (next to LoG2Coop.exe) win over the built-in ones:
  - an entry with the same "id" REPLACES the built-in one,
  - an entry with a new "id" is ADDED.
So you can also keep only your own entries in a file (e.g. one new move) - the rest stays as built in.
If a file has a mistake (a missing comma or quote), the game ignores that file and uses the built-in one.
Tip: paste the file into any "JSON validator" website to find the mistake.

Online: every PC uses its own files for its own player (your moves, your forms). For the same items
everywhere, give your friend the same "content" folder.

Characters are written as: "GOHAN", "PICCOLO", "VEGETA", "TRUNKS", "GOKU", "MR. SATAN" or "ALL".
Colours are hex like a web page: "ff0000" red, "7fd8ff" light blue, "ffffff" white.
Time is in ticks: 60 ticks = 1 second.


skills.json - SPECIAL MOVES
---------------------------
{"id": "kamehameha", "name": "KAMEHAMEHA", "who": ["GOKU"], "level": 1, "ep": 6, "cooldown": 90,
 "type": "beam", "charge": 36, "power": 3.2, "stat": "pwr", "speed": 6, "range": 260, "width": 12,
 "color": "7fd8ff", "sfx": "beam", "info": "shown in the menu"}

  id        a unique name (letters, no spaces)
  name      what the game shows
  who       which characters have it (a list)
  level     the level it unlocks at
  ep        energy it costs
  cooldown  ticks before it can be used again
  type      what it does - one of:
     beam     charge, then a long beam that goes through everything   (charge speed range width)
     volley   several ki blasts in a row                              (count speed range, spread: 1 = fan out)
     bomb     charge, then a ball that explodes on the first foe      (charge speed range radius size)
     dash     fly forward hitting everything you pass                 (speed range)
     slash    a wide cut in front                                     (range)
     stretch  a long, narrow punch                                    (range)
     wave     a blast all around you that throws foes back            (range)
     flash    blinds every foe around you                             (range, stun = ticks they stand still)
     heal     heals part of your health                               (heal: 0.45 = 45%)
     buff     a power-up for a while                                  (buffs: {"str": 1.5, "end": 1.5}, ticks)
  power     how strong: damage = power x the stat (about like 1 = a normal ki blast / punch)
  stat      "pwr" (ki power) or "str" (strength)
  sfx       sound: punch kick ki beam dash slash bomb wave flash heal
  look      the game's own effect for a beam or a ball: blue (Kamehameha), yellow (Final Flash),
            purple (Galick Gun), red (Special Beam Cannon), spirit (Spirit Bomb), bigbang, orange, present

Example - give Goku a Destructo Disc at level 10:
  {"id": "destructo_disc", "name": "DESTRUCTO DISC", "who": ["GOKU"], "level": 10, "ep": 6, "cooldown": 120,
   "type": "beam", "charge": 20, "power": 4.0, "stat": "pwr", "speed": 4, "range": 220, "width": 6, "color": "ffff80"}


forms.json - TRANSFORMATIONS
----------------------------
{"id": "ssj_goku", "name": "SUPER SAIYAN", "who": "GOKU", "level": 18, "set": 61,
 "str": 1.7, "pwr": 1.7, "end": 1.3, "speed": 1.25, "drain_ticks": 90, "aura": "ffe050"}

  set          the look: a sprite set number from your ROM (-1 = keep the normal look)
               Some sets: Gohan 53 55 56 57 58(SSJ) 59(SSJ2) - Goku 60 61(SSJ) - Piccolo 103 104 -
               Vegeta 137 138 139(SSJ) 140(Super Vegeta) - Trunks 128 129 130(SSJ) 132 133 134 135 - Mr. Satan 72
               (any set works - even an enemy's! open the "imported/sprites" folder to see them all)
  str pwr end  multiply strength, ki power, endurance
  speed        multiplies walking speed
  drain_ticks  you lose 1 EP every so many ticks; at 0 EP you change back
  aura         the colour of the aura (leave it out for none)
  tint         colours the sprite (e.g. "ffc0c0" reddish for Kaioken)
  scale        bigger or smaller (1.15 = 15% bigger)
The TRANSFORM button goes to the next form you have unlocked, and from the strongest back to normal.


items.json - ITEMS
------------------
{"id": "senzu", "name": "SENZU BEAN", "hp": 1.0, "ep": 1.0, "max": 10, "drop": 0.015, "price": 600, "color": "9be35a"}

  hp / ep      heal that part of the maximum (1.0 = all)
  buff         "str" "pwr" "end" "speed" or "exp", with "mult" (1.3 = +30%) and "ticks"
  max          how many you can carry
  drop         chance an ordinary foe leaves one (strong foes 3x, the boss 6x)
  price        zeni at the CAPSULE SHOP (menu); 0 = not sold
  "zeni": {"drop": 0.55, "min": 4, "max": 18, "per_level": 2}   how much money foes leave


music.json - MUSIC
------------------
YOUR OWN MUSIC: put the songs in the "music" folder next to LoG2Coop.exe (.ogg or .mp3):
  title  field  cave  lair  boss  victory          e.g. music/field.ogg
  or a place's name: music/west city.ogg plays in West City, music/big mouth.ogg in the Big Mouth,
  music/northern mountains.mp3 in the Northern Mountains (the name the game shows when you walk in)
Listen to them in the game: MENU - OPTIONS - MUSIC TEST (A: next song).
Without a file the game plays little tunes it writes itself from music.json:
  bpm         speed
  lead, bass  notes, one per step (a step is a 16th note): C4 D#4 Bb3 ... "." holds the note, "-" is silence,
              "|" is only to make it easier to read. Higher number = higher octave.
  drums       k = kick, s = snare, h = hi-hat, - = nothing
  lead_wave / bass_wave   square, pulse, triangle, saw, sine

sounds.json - SOUND EFFECTS
---------------------------
The sounds are the game's own samples, read from your ROM into imported/sounds/sfx_00.wav ... sfx_63.wav
(open them in any player). sounds.json says which plays for what - a list means a random one each time:
  "punch": [37, 38],   "ki": [13, 14],   "hit": [34, 35, 36],   "boom": [20, 21] ...
Listen to all 64 in the game: MENU - OPTIONS - SOUND TEST (A: next), then put the numbers you like here.
The names: punch kick ki beam_charge beam dash slash bomb boom wave flash heal hit crit hurt die pickup
item zeni levelup transform menu move error.
Your own file still wins: sounds/<name>.ogg (or .mp3) next to LoG2Coop.exe.


enemies.json - HOW FOES FIGHT
-----------------------------
Every foe fights with ITS OWN ATTACK FROM THE GAME, drawn with the game's own sprites (read from your ROM):
  laser     the flying robots: they get in line with you, then fire a straight zig-zag laser
  fireball  the fire-breathers spit fireballs that burst into flame (big ones leave burning ground)
  bomber    the bandits throw lit bombs in an arc - a ring shows where it lands, run before the fuse burns down
  stomper   the giants stomp: a white shock ring runs out along the ground
  melee     walks up and hits with its own attack pose;  lunger  crouches, then leaps;  slammer  slams the ground
Strong (rare) foes do more: two lasers, three fireballs, three bombs, two rings.
Bosses and world bosses mix their kind's own attack with a charged BEAM (an orb gathers first - get out of
its line!), a ring of fireballs, shock rings and leaps, and call for help when hurt.
"types" in enemies.json says which enemy type number uses which style (taken from the game's own behaviour
data); "groups" is for every other kind; "styles" holds the numbers:
  range, keep (distance it likes), windup, speed, cooldown [min, max], power (x the foe's attack),
  laser: len, life;  bomber: flight, fuse, radius;  stomper: radius, ring_speed;
  boss: every, volley, beam_charge, beam_time, beam_len, beam_width, help_at, help
  {"type": 9, "style": "fireball"}   - the bandits spit fire instead of throwing bombs
The sprites are imported/fx/e_laser.png, e_fire.png, e_bomb.png, e_ring.png, e_beam.png, e_charge.png...


gear.json - GEAR (worn in MENU - GEAR)
--------------------------------------
{"id": "saiyan_armor", "name": "SAIYAN ARMOR", "slot": "armor", "rarity": 2, "level": 6, "end": 6, "drop": 0.004, "price": 900}
  slot      weights, armor, scouter, boots, belt (one of each can be worn)
  rarity    1 common (white), 2 rare (blue), 3 epic (purple), 4 legendary (gold) - only the colour
  level     needed to wear it (foes only drop pieces up to 4 levels above their own)
  str pwr end   added to your stats;  speed exp   +0.1 = +10%
  drop      chance per ordinary foe (strong foes 3x, bosses 6x, world bosses 12x + a shower of loot)
  price     0 = not in the shop (only from foes - or from a friend: gear can be given like items)


quests.json - MISSIONS (MENU - MISSIONS)
----------------------------------------
{"id": "big_game", "name": "BIG GAME", "info": "Beat 5 giants.", "type": "kill", "target": "big", "count": 5,
 "level": 6, "reward": {"zeni": 400, "exp": 1.2, "items": {"saiyan_armor": 1}}}
  type      kill   - target: any, elite, boss, worldboss, human, animal, robot, big, or an enemy type number
            visit  - where: a part of a place's name ("COAST", "FORTRESS"...)
            level  - count = the level to reach
  level     shows up from this level
  repeat    true = starts again when done
  reward    zeni, exp (1.0 = one whole level's worth), items (item or gear ids with how many)
Friends in the same place all get credit for every foe beaten, so missions are done together.


WORLD BOSS
----------
Every 12-18 minutes (the first after 5) a WORLD BOSS appears in a random place - everyone in the world
is told where. Beat it together: big EXP, a shower of loot, and the LEGEND HUNTERS mission.
Its moves are the "boss" style in enemies.json.

PEOPLE - people.json
The people in the lands come from your ROM (where they stand, how they look, what they say).
people.json adds to that:
  "talk_range"  how near (pixels) you must stand to talk with A
  "heroes"      names whose lines are the player's own words (left out)
  "names"       a name for a look (sprite set number) the game never names, e.g. "95": "NAMEK"
  "quiet"       what people say when the game gives them nothing: by name, or "default"
  "lines"       new lines for one person: "4_3:0": ["Hi!", "Bye!"]  (map 4_3, person number 0)
  "hide"        people to leave out: ["4_3:2"]
  "add"         new people: "4_3": [{"x": 300, "y": 1200, "set": 80, "name": "BAKER", "lines": ["Fresh bread!"]}]
  "fix_names"   a name the game's text spells oddly -> the right one
Missions from people (quests.json): "from": "HERCULE" - the mission opens when you talk to Hercule;
"type": "talk", "who": "TRENT" - done when you talk to Trent.

PLAYING TOGETHER - social.json (MENU - FRIENDS)
  "party": {"share": 0.5}       a party member somewhere else still gets this part of your exp (and kill missions count)
  "duel": {"damage": 0.4,       blows in a duel hurt this much of their normal strength
           "max_hit": 0.2,      one blow takes at most this part of your health
           "countdown": 3}      seconds before a duel starts
A duel never knocks anyone out: the loser goes back to full health. A trade only happens when both
players pressed READY on the very same offer.

THE HEROES' OWN ATTACKS - rom_specials.json
kame (Goku), sbc (Piccolo), masenko (Gohan), bigki (Vegeta), burning (Trunks): measured from the game.
  power       how hard it hits
  max         a beam's full length in pixels (56 in the game) - make it longer for a stronger beam
  speed       how many pixels a beam grows / the ball flies each frame
  range       how far a ball flies
  pose_charge / pose_fire   the hero's frame per direction [animation, frame, pixels to the right]
A skill in skills.json uses one with "rom": "kame" (and so on).


story.json - A GAME OF YOUR OWN (DEV TOOLS - STORY)
--------------------------------------------------
{"story": {"title": "MY STORY", "subtitle": "", "hero": "GOKU", "start_map": "land/0/0", "x": 8088,
 "y": 9632, "intro_event": "my_intro", "credits": ["MY STORY", "", "THANKS FOR PLAYING!"],
 "credits_music": "victory"}}

  With a title the main menu shows the story with 3 save slots of its own. intro_event is an
  events.json id played once when a new story starts; the THE_END event step shows the credits.
  The story steps (move, camera, boss_fight, var, timer, companion, switch_hero, open_area, save,
  the_end...) are described in "DEV TOOLS.txt", part 8.
