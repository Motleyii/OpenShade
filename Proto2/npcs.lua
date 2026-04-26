--============================================================--
-- npcs.lua
--
-- PURPOSE:
--   Defines all NPC (Non-Player Character) prototypes used
--   by the game world. Each entry in this file represents a
--   static NPC definition that can be instantiated at
--   runtime and interact with players through combat,
--   movement, spells, and puzzles.
--
--   npcs.lua contains NPC *definitions only*.
--   All dynamic and transient state is stored separately
--   in per-NPC `np` (non-persistent) runtime tables.
--
--============================================================--
--
-- NPC TABLE STRUCTURE:
--
--   Each NPC is stored as an entry in the npcs table,
--   indexed by a numeric NPC ID:
--
--     npcs[npc_id] = { ... }
--
--============================================================--
--
-- NPC FIELDS:
--
--   id
--     Numeric NPC identifier. Must match the table index.
--
--   name
--     Canonical display name of the NPC. Used for messaging,
--     combat output, inspection, and reference resolution.
--
--   noun
--     Array of alternative words that may be used to refer
--     to this NPC in commands, spells, and puzzles.
--     Matched case-insensitively by the parser.
--     Example: { "GOBLIN", "GUARD", "SENTRY" }
--
--   here
--     Short descriptive string shown when the NPC is present
--     in a room (e.g. "A goblin lurks here.").
--
--   enters
--     Message displayed to players in a room when this NPC
--     enters from another room (e.g. "A goblin slinks in.").
--
--   leaves
--     Message displayed to players in a room when this NPC
--     leaves to another room (e.g. "A goblin slinks away.").
--
--   desc
--     Full descriptive text shown when the NPC is examined
--     or inspected via wizard tools.
--
--   level
--     Numeric level of the NPC. Used for scaling combat
--     difficulty, rewards, and behavior.
--
--   stamina
--     Initial stamina value for the NPC at spawn time.
--     May be reduced by combat or actions.
--
--   max_stamina
--     Maximum stamina value for the NPC. Acts as the NPC’s
--     primary durability resource and upper bound for
--     stamina recovery.
--
--   power
--     Offensive capability of the NPC, typically used in
--     combat damage and attack calculations.
--
--   speed
--     Number of game ticks between autonomous NPC movement
--     attempts. Lower values result in more frequent movement.
--     Used by the game loop to determine when an NPC may
--     move between rooms independently.
--
--   flags
--     Table of boolean attributes describing grammatical,
--     behavioral, or semantic properties of the NPC.
--     Common flags include:
--
--       ismale      — NPC is grammatically masculine
--       isplural    — NPC name is plural
--       isvowel     — NPC name begins with a vowel sound
--       aggressive  — NPC may initiate combat automatically
--
--   home
--     Default room ID where the NPC originates or is
--     considered to belong.
--
--   respawn
--     Array of room IDs indicating possible respawn locations
--     when the world resets.
--
--   inventory
--     Optional table describing objects carried by the NPC
--     when spawned.
--
--   puzzles
--     Optional table of puzzle entries associated with this
--     NPC. Each puzzle defines conditional verb-based
--     interactions (see puzzle.lua).
--
--   np
--     Non-persistent runtime state table.
--     This field is NOT saved to disk and is populated at
--     runtime. Common runtime fields include:
--
--       location      — Current room ID
--       state         — Numeric state used by puzzles
--       stamina       — Current stamina
--       move_counter  — Ticks since last movement
--       target        — Current combat target, if any
--
--     The `np` table must never be edited in npcs.lua.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * npcs.lua defines static NPC prototypes only.
--
--   * All mutation of NPC state occurs at runtime via
--     combat.lua, movement.lua, puzzle.lua, and the game loop.
--
--   * NPC noun matching follows the same rules as objects,
--     allowing flexible player references.
--
--   * Any changes to NPC fields should be reflected in
--     wizard inspection tools and editors.
--
--============================================================--

return {
	[0]=  {id=0,  name="NPC0",    noun={"NPC0"},    power=1,    max_stamina=1,     value=1,    speed=10, enters="NPC0",                                                         leaves="NCP0",                                                        here="NCP0",                                                    path={0}, flags=nil, puzzles=nil, np=nil},
	[1]=  {id=1,  name="bear",    noun={"bear"},    power=16,   max_stamina=275,   value=125,  speed=15, enters="A huge grizzly bear pads along.",                              leaves="The bear wanders off, snuffling loudly as it does so.",       here="A bear with big, doleful eyes snuffles nearby.",          path={138, 134, 132, 136, 138, 134, 133, 136, 137, 133, 132, 137}, flags=nil, puzzles=nil, np=nil},
	[2]=  {id=2,  name="beggar",  noun={"beggar"},  power=20,   max_stamina=300,   value=150,  speed=10, enters="A beggar limps in, holding a begging bowl before him.",        leaves="The beggar shuffles slowly out, his rags trailing behind...", here="A beggar watches you, a crafty gleam in his eyes…",       path={168, 170, 172, 151, 152, 163, 162, 167}, flags=nil, puzzles=nil, np=nil},
	[3]=  {id=3,  name="crow",    noun={"crow"},    power=5,    max_stamina=100,   value=50,   speed=50, enters="A malevolent black crow flaps in, crying \"corpse, corpse\".", leaves="The black crow flaps out in search of carrion.",              here="A crow flaps towards you, striking at your eyes!",        path={22, 5, 536, 537, 98, 96, 94, 92, 93, 536, 537, 2, 3, 4}, flags=nil, puzzles=nil, np=nil},
	[4]=  {id=4,  name="death",   noun={"death"},   power=18,   max_stamina=300,   value=145,  speed=15, enters="Death strides in, carrying a long scythe... ",                 leaves="Death decides not to kill you and leaves.",                   here="You sense a deathly presence here....",                   path={559, 563, 559, 558, 559, 555}, flags=nil, puzzles=nil, np=nil},
	[5]=  {id=5,  name="deer",    noun={"deer"},    power=8,    max_stamina=100,   value=50,   speed=50, enters="A large red deer stalks in.",                                  leaves="The deer stalks gracefully away.",                            here="A deer grazes nearby.",                                   path={126, 127, 121, 57, 55, 6, 55, 57, 122, 123, 124, 125}, flags=nil, puzzles=nil, np=nil},
	[6]=  {id=6,  name="dwarf",   noun={"dwarf"},   power=20,   max_stamina=140,   value=70,   speed=70, enters="A dwarf housekeeper stumps in.",                               leaves="The dwarf housekeeper stumps out.",                           here="The dwarf housekeeper eyes you with suspicion.",          path={500, 504, 501, 503, 508, 509, 510, 511, 512, 513, 497, 494, 491, 489, 492, 495, 498, 502, 506, 499, 505}, flags=nil, puzzles=nil, np=nil},
	[7]=  {id=7,  name="ghost",   noun={"ghost"},   power=5,    max_stamina=125,   value=75,   speed=75, enters="A ghost glides in, moaning horribly!",                         leaves="The ghost glides out..",                                      here="A ghost floats before you!",                              path={44, 47, 45, 44, 43, 42, 43}, flags=nil, puzzles=nil, np=nil},
	[8]=  {id=8,  name="girl",    noun={"girl"},    power=1000, max_stamina=1000,  value=1000, speed=10, enters="The Strange Little Girl drifts in..",                          leaves="The Strange Little Girl drifts out..",                        here="The Strange Little Girl is standing nearby.",             path={139, 138, 137, 134, 133, 132, 131, 130, 129, 128, 127, 125, 124, 40, 21, 13, 415, 414, 6, 7, 8, 53, 49, 54, 61, 71, 72, 73}, flags=nil, puzzles=nil, np=nil},
	[9]=  {id=9,  name="guard",   noun={"guard"},   power=8,    max_stamina=350,   value=80,   speed=80, enters="A burly guard strides in.",                                    leaves="The guard strides out.",                                      here="A guard stands rigidly to attention near you.",           path={8, 53, 49, 54, 61, 62, 61, 54, 6, 7, 8, 9, 10, 9}, flags=nil, puzzles=nil, np=nil},
	[10]= {id=10, name="hermit",  noun={"hermit"},  power=18,   max_stamina=400,   value=70,   speed=70, enters="The hermit stamps angrily in.",                                leaves="The hermit glares angrily at you before stamping out.",       here="The hermit looks at you with evident distaste.",          path={754, 752, 753, 752, 754, 761, 755, 761, 755, 756, 757, 755}, flags=nil, puzzles=nil, np=nil},
	[11]= {id=11, name="hound",   noun={"hound"},   power=8,    max_stamina=130,   value=60,   speed=60, enters="DOES NOT MOVE",                                                leaves="DOES NOT MOVE",                                               here="The hound of San Simeon guards the stairs.",              path={503}, flags=nil, puzzles=nil, np=nil},
	[12]= {id=12, name="leech",   noun={"leech"},   power=40,   max_stamina=50000, value=100,  speed=10, enters="You feel a light, slimy touch caress your legs...",            leaves="Something slimy kisses your legs and drifts away…",           here="Occasional dark shapes slither through the water.",       path={748, 742, 743, 744, 745, 746, 747}, flags=nil, puzzles=nil, np=nil},
	[13]= {id=13, name="lion",    noun={"lion"},    power=20,   max_stamina=275,   value=80,   speed=80, enters="An enormous lion pads in, head swinging from side to side.",   leaves="The lion decides to ignore you and pads out.",                here="A lion idly watchs you, wondering what you taste like.",  path={406, 401, 402, 403, 404, 406, 401, 402, 404, 406, 402, 403, 404, 405, 401, 402, 403, 405}, flags=nil, puzzles=nil, np=nil},
	[14]= {id=14, name="lioness", noun={"lioness"}, power=20,   max_stamina=350,   value=80,   speed=80, enters="A lioness prowls in, looking dangerously hungry.",             leaves="The lioness wonders where her cub has got to and leaves.",    here="A magnificent lioness eyes you up, licking her lips.",    path={394, 399, 393, 394, 395, 409, 393}, flags=nil, puzzles=nil, np=nil},
	[15]= {id=15, name="morloch", noun={"morloch"}, power=20,   max_stamina=300,   value=170,  speed=17, enters="The Morloch shuffles in, bulbous eyes glowing evilly!",        leaves="The Morloch peers about, then shuffles away.",                here="The huge eyes of an evil Morloch stare intently at you.", path={385, 387, 371, 370, 368, 367, 374, 377, 378, 383, 378, 384, 379, 380}, flags=nil, puzzles=nil, np=nil},
	[16]= {id=16, name="mouse",   noun={"mouse"},   power=15,   max_stamina=225,   value=65,   speed=65, enters="A mouse scampers in, whiskers twiching nervously.",            leaves="The mouse scurries out, nose to the ground.",                 here="A mouse scurries about in search of anything edible.",    path={62, 61, 71, 72, 74, 82, 64, 63}, flags=nil, puzzles=nil, np=nil},
	[17]= {id=17, name="sprite",  noun={"sprite"},  power=15,   max_stamina=30,    value=50,   speed=50, enters="DOES NOT MOVE",                                                leaves="DOES NOT MOVE",                                               here="A tree sprite dances a merry jig before you.",            path={130}, flags=nil, puzzles=nil, np=nil},
	[18]= {id=18, name="thief",   noun={"thief"},   power=12,   max_stamina=300,   value=80,   speed=80, enters="The thief slinks in, carrying a bag over one shoulder.",       leaves="The thief sidles into the shadows, and is gone.",             here="A thief lurks near, with evil intent on his face.",       path={54, 4, 13, 82, 182, 171, 169, 8, 10, 54, 13, 104, 82, 171, 169, 479, 10}, flags=nil, puzzles=nil, np=nil},
	[20]= {id=20, name="wraith",  noun={"wraith"},  power=30,   max_stamina=200,   value=125,  speed=12, enters="A wraith of doom floats in.",                                  leaves="The wraith of doom wails evilly and floats out.",             here="A wraith hangs evilly in the air.",                       path={455, 459, 460, 459, 457, 458, 454, 455, 459, 460, 459, 457, 458, 454, 456, 459, 460, 456, 457, 458, 454, 456, 459, 456, 457, 458, 454, 456, 459}, flags=nil, puzzles=nil, np=nil},
	[21]= {id=21, name="zombie",  noun={"zombie"},  power=12,   max_stamina=666,   value=350,  speed=35, enters="A decaying Zombie shuffles slowly in.",                        leaves="The rotting Zombie slowly shuffles out.",                     here="The rotting figure of a Zombie stares blankly at you.",   path={728, 729, 730, 729, 728, 727, 724, 725, 763, 764, 765, 731, 765, 726, 725, 724, 727}, flags=nil, puzzles=nil, np=nil},
	[22]= {id=22, name="cub",     noun={"cub"},     power=12,   max_stamina=300,   value=50,   speed=0,  enters="A lion cub staggers unsteadily in.",                           leaves="The lion cub mewls and wanders out looking for its mother.",  here="A playful lion cub nibbles gently at your leg.",          path={408}, flags=nil, puzzles=nil, np=nil},
}