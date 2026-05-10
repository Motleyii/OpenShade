--============================================================--
-- objects.lua
--
-- PURPOSE:
--   Defines all object prototypes used by the game world.
--   Each entry in this file represents a static object
--   definition that can exist in rooms, player inventories,
--   or elsewhere in the world at runtime.
--
--   objects.lua contains object *definitions only*.
--   Runtime state for objects is stored separately in
--   per-object `np` (non-persistent) tables.
--
--============================================================--
--
-- OBJECT TABLE STRUCTURE:
--
--   Each object is stored as an entry in the objects table,
--   indexed by numeric object ID:
--
--     objects[object_id] = { ... }
--
--============================================================--
--
-- OBJECT FIELDS:
--
--   id
--     Numeric object identifier. Must match the table index.
--
--   name
--     The canonical display name of the object. Used for
--     inspection, messaging, and default identification.
--
--   noun
--     Array of alternative words that may be used to refer
--     to this object in commands and puzzles. These are
--     matched case-insensitively by the parser.
--     Example: { "SWORD", "BLADE", "WEAPON" }
--
--   desc
--     The full description string shown when the object is
--     examined in a room or via inspection commands.
--
--   value
--     Numeric value of the object, typically used for scoring,
--     economy, or trading logic.
--
--   power
--     Numeric power rating of the object. Interpretation is
--     game-specific and may relate to combat, magic, or effects.
--
--   weight
--     Numeric weight of the object, usually in arbitrary units.
--     Used for inventory limits, encumbrance, or movement cost.
--
--   home
--     Default room ID where the object originates or is
--     considered to belong. Used for placement and reference.
--
--   respawn
--     Array of room IDs indicating possible respawn locations
--     for the object. When an object is reset, one of these
--     locations may be chosen.
--
--   flags
--     Table of boolean attributes describing grammatical or
--     semantic properties of the object.
--     Common flags include:
--
--       ismale     — Object is grammatically masculine
--       isplural   — Object name is plural
--       isvowel    — Object name begins with a vowel sound
--
--     These flags are primarily used for correct message
--     formatting and language rules.
--
--   puzzles
--     Optional table of puzzle entries associated with this
--     object. Each puzzle defines verb-based conditional
--     behavior (see puzzle.lua). If nil, the object has
--     no puzzle interactions.
--
--   np
--     Non-persistent runtime state table.
--     This field is NOT saved to disk and is populated at
--     runtime. Common runtime fields include:
--
--       location   — Current room ID, if the object is placed
--       state      — Numeric state used by puzzles
--
--     The `np` table must never be edited in objects.lua.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * objects.lua defines static prototypes only.
--
--   * Do not store runtime state directly on object fields
--     outside of the `np` table.
--
--   * All references to objects in commands, spells, or
--     puzzles resolve to these definitions plus runtime `np`.
--
--   * Any change to field meanings should be reflected in
--     inspection tools (e.g. XO) and editors.
--
--============================================================--

return {
	[0]=   {id=0,   name="OBJECT 0",                      noun={"OBJECT0"},                              desc="OBJECT0",                                                       value=1,   power=1,  weight=1,     home=0,   respawn={0, 1},               flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[1]=   {id=1,   name="brass ring",                    noun={"RING", "BRASS"},                        desc="A solid brass ring lies on the ground, gleaming brightly.",     value=5,   power=0,  weight=5,     home=7,   respawn={186, 396, 235, 29},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[2]=   {id=2,   name="gold plate",                    noun={"PLATE"},                                desc="A shining gold plate lies before you.",                         value=87,  power=0,  weight=2000,  home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[3]=   {id=3,   name="black vial",                    noun={"BLACK", "VIAL"},                        desc="A small black vial is here.",                                   value=25,  power=0,  weight=150,   home=243, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[4]=   {id=4,   name="finely balanced blade",         noun={"SABRE", "FBB", "BLADE"},                desc="A finely balanced blade glints wickedly here.",                 value=0,   power=30, weight=1000,  home=187, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[5]=   {id=5,   name="jade necklace",                 noun={"NECKLACE", "JADE"},                     desc="There is a fine Jade necklace before you.",                     value=50,  power=0,  weight=500,   home=5,   respawn={539, 75, 571, 416},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[6]=   {id=6,   name="golden chain",                  noun={"CHAIN", "GOLD"},                        desc="A valuable gold chain is here.",                                value=160, power=0,  weight=500,   home=228, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[7]=   {id=7,   name="Bomb",                          noun={"BOMB", "UXB", "SMALL", "BALL"},         desc="A small ball with a fuse hanging out lies on the ground.",      value=1,   power=1,  weight=2000,  home=5,   respawn={187, 303, 397, 2},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[8]=   {id=8,   name="gold horseshoe",                noun={"GOLD", "SHOE", "HORSESHOE"},            desc="On the ground nearby lies a fabulous golden horseshoe!",        value=100, power=0,  weight=1000,  home=41,  respawn={328, 46, 418, 160},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[9]=   {id=9,   name="rough diamond",                 noun={"DIAMOND"},                              desc="A rough, uncut diamond sits on the ground here.",               value=150, power=0,  weight=200,   home=467, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[10]=  {id=10,  name="enraged Terrapin",              noun={"TERRAPIN"},                             desc="An enraged Terrapin crawls about in the dust here.",            value=25,  power=0,  weight=100,   home=21,  respawn=nil,                  flags={ismale=false, isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[11]=  {id=11,  name="bag of gold coins",             noun={"COINS", "GOLD", "BAG"},                 desc="A small bag of gold coins lies here.",                          value=75,  power=0,  weight=1000,  home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[12]=  {id=12,  name="football",                      noun={"BALL", "FOOTBALL"},                     desc="A large football sits here, waiting to be kicked.",             value=0,   power=0,  weight=10000, home=356, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[13]=  {id=13,  name="ruby",                          noun={"RUBY"},                                 desc="There is a deep red ruby on the floor here.",                   value=100, power=0,  weight=100,   home=428, respawn={109, 741, 449, 453}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[14]=  {id=14,  name="rusty coin",                    noun={"RUSTY", "COIN"},                        desc="A small rusty coin sits before you.",                           value=10,  power=0,  weight=10,    home=4,   respawn={664, 740, 441, 744}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[15]=  {id=15,  name="portrait of a princess",        noun={"PORTRAIT"},                             desc="A portrait of a princess catches your eye.",                    value=100, power=0,  weight=2000,  home=431, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[16]=  {id=16,  name="sharp knife",                   noun={"KNIFE"},                                desc="A fine cooking knife has been dropped here.",                   value=0,   power=5,  weight=50,    home=752, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[17]=  {id=17,  name="jewelled clasp",                noun={"CLASP"},                                desc="A jewelled clasp lies here.",                                   value=125, power=0,  weight=100,   home=451, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[18]=  {id=18,  name="mild unassuming rat",           noun={"RAT"},                                  desc="A mild and unassuming rat scurries around your feet.",          value=25,  power=25, weight=100,   home=563, respawn={387, 175, 124, 662}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[19]=  {id=19,  name="trampette",                     noun={"TRAMPETTE"},                            desc="A heavy looking trampette has been left here.",                 value=0,   power=0,  weight=3260,  home=313, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[20]=  {id=20,  name="shortsword",                    noun={"SHORTSWORD", "SWORD", "SS"},            desc="A worn shortsword lies nearby, the blade dulled with use.",     value=0,   power=30, weight=1100,  home=404, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[21]=  {id=21,  name="slimy creature repellant",      noun={"REPELLANT"},                            desc="A wedge of Ab's Slimy Creature Repellant lies before you.",     value=0,   power=0,  weight=50,    home=191, respawn={93, 330, 423, 15},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[22]=  {id=22,  name="wooden crucifix",               noun={"CRUCIFIX", "WOODEN"},                   desc="A carved wooden crucifix has been dropped here.",               value=0,   power=0,  weight=50,    home=329, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[23]=  {id=23,  name="glass cross",                   noun={"GLASS", "CROSS"},                       desc="There is an elaborate glass cross here.",                       value=0,   power=0,  weight=200,   home=194, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[24]=  {id=24,  name="ornate key",                    noun={"KEY", "ORNATE"},                        desc="A fine ornate key lies before you.",                            value=0,   power=0,  weight=62,    home=559, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[25]=  {id=25,  name="cleaning rag",                  noun={"RAG", "CLEANING"},                      desc="There is a cleaning and polishing rag on the floor.",           value=0,   power=0,  weight=10,    home=254, respawn={530, 753, 66, 77},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[26]=  {id=26,  name="gilded canary",                 noun={"CANARY"},                               desc="A gilded canary sits here, looking almost alive.",              value=150, power=0,  weight=550,   home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[27]=  {id=27,  name="stepladder",                    noun={"LADDER", "STEPLADDER"},                 desc="There is a large wooden stepladder here.",                      value=0,   power=0,  weight=1750,  home=535, respawn={513, 537, 494, 489}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[28]=  {id=28,  name="medallion",                     noun={"MEDALLION"},                            desc="A fancy medallion lies before you.",                            value=60,  power=0,  weight=250,   home=324, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[29]=  {id=29,  name="chalice",                       noun={"CHALICE"},                              desc="There is a chalice here.",                                      value=35,  power=0,  weight=380,   home=327, respawn={522, 419, 321, 495}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[30]=  {id=30,  name="silver letter opener",          noun={"SILVER"},                               desc="There is a sharp, silver letter opener here.",                  value=35,  power=5,  weight=150,   home=331, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[31]=  {id=31,  name="glass slipper",                 noun={"GLASS", "SLIPPER"},                     desc="A small glass slipper is here, waiting for the correct foot.",  value=20,  power=0,  weight=50,    home=321, respawn={189, 65, 355, 312},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[32]=  {id=32,  name="Deadly Ninja Throwing Cabbage", noun={"CABBAGE"},                              desc="A peculiarly shaped cabbage lies before you.",                  value=0,   power=18, weight=30,    home=279, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[33]=  {id=33,  name="gold seal",                     noun={"GOLD", "SEAL"},                         desc="A magnificent Gold Seal of State has been discarded here.",     value=175, power=0,  weight=50,    home=451, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[34]=  {id=34,  name="blue potato",                   noun={"BLUE", "POTATO"},                       desc="There is a fresh blue potato here.",                            value=0,   power=0,  weight=50,    home=491, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[35]=  {id=35,  name="pile of chips",                 noun={"CHIPS"},                                desc="There is a pile of greasy but delicious looking chips here.",   value=0,   power=0,  weight=50,    home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[36]=  {id=36,  name="blue vial",                     noun={"BLUE", "VIAL"},                         desc="A small blue vial lies temptingly here.",                       value=25,  power=0,  weight=140,   home=357, respawn={324, 234, 224, 805}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[37]=  {id=37,  name="smooth stone",                  noun={"SMOOTH", "STONE"},                      desc="A smooth stone sits solidly on the floor here.",                value=100, power=15, weight=25,    home=84,  respawn={171, 126, 741, 540}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[38]=  {id=38,  name="rusty longsword",               noun={"RUSTY", "SWORD", "LS"},                 desc="There is a rusty, but functional, longsword here.",             value=0,   power=30, weight=1000,  home=260, respawn={84, 817, 764, 185},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[39]=  {id=39,  name="clear vial",                    noun={"CLEAR", "VIAL"},                        desc="A small clear vial lies temptingly here.",                      value=150, power=0,  weight=300,   home=523, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[40]=  {id=40,  name="golden crown",                  noun={"CROWN"},                                desc="Your heart races as you espy a magnificent golden crown!",      value=200, power=0,  weight=1000,  home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[41]=  {id=41,  name="brown key",                     noun={"BROWN", "KEY"},                         desc="There is a small, brown key here.",                             value=0,   power=0,  weight=34,    home=222, respawn={402, 88, 221, 79},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[42]=  {id=42,  name="rocking horse",                 noun={"ROCKING", "HORSE"},                     desc="There is a child's rocking horse here.",                        value=0,   power=0,  weight=1250,  home=540, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[43]=  {id=43,  name="wooden statue",                 noun={"WOODEN", "STATUE"},                     desc="There is a large, indescribably ugly wooden statue here.",      value=75,  power=0,  weight=750,   home=88,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[44]=  {id=44,  name="ebony rod",                     noun={"ROD", "WAND", "EBONY"},                 desc="An elaborately carved ebony rod lies before you.",              value=10,  power=15, weight=250,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[45]=  {id=45,  name="black pearl",                   noun={"BLACK", "PEARL"},                       desc="A strange, lustrous black pearl has been left here.",           value=150, power=0,  weight=100,   home=479, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[46]=  {id=46,  name="blue crystal",                  noun={"CRYSTAL", "BLUE"},                      desc="A blue crystal rests here, glowing with strange energies.",     value=100, power=0,  weight=100,   home=234, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[47]=  {id=47,  name="pile of bones",                 noun={"BONES", "PILE"},                        desc="An ancient pile of bones lies in a heap here.",                 value=75,  power=0,  weight=995,   home=120, respawn={382, 135, 52, 737},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[48]=  {id=48,  name="diamond brooch",                noun={"DIAMOND", "BROOCH"},                    desc="You notice a glittering brooch lying at your feet.",            value=125, power=0,  weight=100,   home=110, respawn={113, 67, 570, 496},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[49]=  {id=49,  name="coil of rope",                  noun={"COIL", "ROPE"},                         desc="A long coil of fine, strong rope lies here.",                   value=0,   power=0,  weight=100,   home=55,  respawn={384, 276, 90, 138},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[50]=  {id=50,  name="lost chord",                    noun={"LOST", "CHORD"},                        desc="You hear the sound of a lost chord.",                           value=0,   power=0,  weight=25,    home=504, respawn={224, 504, 279, 408}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[51]=  {id=51,  name="woodsmans Axe",                 noun={"AXE"},                                  desc="A large, sharp woodsmans axe has been left here.",              value=0,   power=20, weight=3000,  home=135, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[52]=  {id=52,  name="golden helmet",                 noun={"HELMET"},                               desc="An ornate, highly decorated golden helmet catchs your eye.",    value=150, power=0,  weight=1000,  home=405, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[53]=  {id=53,  name="golden acorn",                  noun={"GOLD", "ACORN"},                        desc="A glint of light from a golden acorn catches your eye.",        value=60,  power=0,  weight=100,   home=144, respawn={88, 124, 143, 417},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[54]=  {id=54,  name="trinket",                       noun={"TRINKET"},                              desc="An unidentifiable but not unvaluable trinket gleams brightly.", value=150, power=0,  weight=205,   home=185, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[55]=  {id=55,  name="pewter goblet",                 noun={"PEWTER", "GOBLET"},                     desc="A sadly empty pewter goblet is here,",                          value=15,  power=0,  weight=100,   home=187, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[56]=  {id=56,  name="delicate ice crystal",          noun={"ICE", "CRYSTAL"},                       desc="A delicate ice crystal glistens nearby.",                       value=50,  power=5,  weight=50,    home=383, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[57]=  {id=57,  name="pendant",                       noun={"PENDANT"},                              desc="There is a pendant here.",                                      value=37,  power=0,  weight=150,   home=184, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[58]=  {id=58,  name="champagne cork",                noun={"CORK"},                                 desc="A champagne cork lies here, no bottle unfortunately.",          value=25,  power=0,  weight=3,     home=538, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[59]=  {id=59,  name="jewelled Egg",                  noun={"EGG"},                                  desc="There is a fabulously jewelled egg here.",                      value=75,  power=0,  weight=85,    home=184, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[60]=  {id=60,  name="brass key",                     noun={"BRASS", "KEY"},                         desc="There is a large, brass key lying here.",                       value=2,   power=0,  weight=200,   home=45,  respawn={135, 545, 19, 357},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[61]=  {id=61,  name="bronze key",                    noun={"BRONZE", "KEY"},                        desc="There is a bronze key here.",                                   value=0,   power=0,  weight=20,    home=145, respawn={328, 509, 422, 223}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[62]=  {id=62,  name="book of poems by Milo D Milo",  noun={"BOOK"},                                 desc="Milo D. Milo's Book of Poetry lies before you.",                value=75,  power=0,  weight=200,   home=279, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[63]=  {id=63,  name="figurine",                      noun={"FIGURINE"},                             desc="There is a finely carved figurine here.",                       value=100, power=0,  weight=100,   home=540, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[64]=  {id=64,  name="dusty cloak",                   noun={"CLOAK", "DUSTY"},                       desc="A dark, dusty cloak lies on the ground.",                       value=108, power=0,  weight=500,   home=167, respawn={258, 731, 188, 538}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[65]=  {id=65,  name="Bomb",                          noun={"BOMB", "XB", "SMALL", "BALL"},          desc="A small ball with a fuse hanging out lies on the ground.",      value=125, power=0,  weight=2000,  home=172, respawn={2, 397, 303, 187},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[66]=  {id=66,  name="quicklime pellet",              noun={"PELLET", "QUICKLIME"},                  desc="A small pellet of quicklime lies here.",                        value=0,   power=0,  weight=100,   home=191, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[67]=  {id=67,  name="platinum key",                  noun={"PLATINUM", "KEY"},                      desc="There is a shiny key here, apparently made from platinum.",     value=60,  power=0,  weight=30,    home=65,  respawn={816, 763, 730, 248}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[68]=  {id=68,  name="burnished key",                 noun={"BURNISHED", "KEY"},                     desc="A burnished key lies before you.",                              value=0,   power=0,  weight=20,    home=123, respawn={730, 174, 513, 234}, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[69]=  {id=69,  name="steel key",                     noun={"STEEL", "KEY"},                         desc="There is a steel key on the ground.",                           value=0,   power=0,  weight=25,    home=95,  respawn={357, 154, 81, 220},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[70]=  {id=70,  name="corroded key",                  noun={"CORRODED", "KEY"},                      desc="There is a highly corroded (but still usable) key here.",       value=0,   power=0,  weight=15,    home=18,  respawn={371, 95, 84, 222},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[71]=  {id=71,  name="crystal of jet and gold",       noun={"CRYSTAL"},                              desc="A fine crystal of darkest Jet, shot with gold, lies here.",     value=160, power=0,  weight=275,   home=800, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[72]=  {id=72,  name="lead bar",                      noun={"BAR", "LEAD"},                          desc="A large lead bar lies on the floor here.",                      value=125, power=5,  weight=3500,  home=191, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[73]=  {id=73,  name="sceptre",                       noun={"SCEPTRE"},                              desc="There is a sceptre here.",                                      value=37,  power=0,  weight=1200,  home=507, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[74]=  {id=74,  name="brick",                         noun={"ROCK", "BRICK"},                        desc="There is a large square brick here.",                           value=0,   power=10, weight=2000,  home=180, respawn={171, 110, 86, 329},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[75]=  {id=75,  name="necklace made of teeth",        noun={"NECKLACE"},                             desc="There is a rough necklace here, made out of old teeth.",        value=100, power=10, weight=1000,  home=387, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[76]=  {id=76,  name="dark gemstone",                 noun={"DARK", "GEMSTONE"},                     desc="Lying before you is a dark gemstone of strange beauty.",        value=35,  power=0,  weight=25,    home=784, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[77]=  {id=77,  name="bone",                          noun={"BONE"},                                 desc="Some flies buzz around a horribly fresh looking bone.",         value=150, power=0,  weight=600,   home=400, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[78]=  {id=78,  name="unicorns horn",                 noun={"HORN"},                                 desc="A brightly coloured unicorns horn lies before you.",            value=50,  power=5,  weight=100,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[79]=  {id=79,  name="ripe apple",                    noun={"RIPE", "APPLE"},                        desc="A fine, ripe apple has been dropped here.",                     value=5,   power=0,  weight=2500,  home=123, respawn={186, 47, 495, 327},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[80]=  {id=80,  name="gold apple",                    noun={"GOLD", "APPLE"},                        desc="There is a large, gold apple here.",                            value=75,  power=0,  weight=2499,  home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[81]=  {id=81,  name="red rose",                      noun={"RED", "ROSE"},                          desc="A beautiful red rose fills the air with a heavenly scent.",     value=0,   power=0,  weight=10,    home=67,  respawn={511, 65, 145, 326},  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[82]=  {id=82,  name="sovereign",                     noun={"SOVEREIGN"},                            desc="There is a sovereign here.",                                    value=80,  power=0,  weight=30,    home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[83]=  {id=83,  name="shield",                        noun={"SHIELD"},                               desc="There's a useful looking shield here, dented but serviceable.", value=100, power=5,  weight=1500,  home=408, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[84]=  {id=84,  name="gold brick",                    noun={"GOLD", "BRICK"},                        desc="Somehow an ordinary gold brick has been dropped here.",         value=160, power=0,  weight=1400,  home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[85]=  {id=85,  name="bracelet",                      noun={"BRACELET"},                             desc="There is a fancy bracelet here.",                               value=38,  power=0,  weight=50,    home=532, respawn={118, 73, 243, 48},   flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[86]=  {id=86,  name="gold fish",                     noun={"GOLD", "FISH"},                         desc="A small, gold fish lies on the floor before you.",              value=125, power=0,  weight=250,   home=192, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[87]=  {id=87,  name="empty glass",                   noun={"EMPTY", "GLASS"},                       desc="There is an ordinary, empty drinking glass here.",              value=0,   power=0,  weight=127,   home=330, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[88]=  {id=88,  name="drinking cup",                  noun={"CUP"},                                  desc="There is a drinking cup here.",                                 value=58,  power=0,  weight=250,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[89]=  {id=89,  name="mayors chain",                  noun={"CHAIN", "MAYORS"},                      desc="A large, elaborate mayors chain lies here.",                    value=25,  power=15, weight=1100,  home=529, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[90]=  {id=90,  name="mace",                          noun={"MACE"},                                 desc="There is a mace here.",                                         value=20,  power=0,  weight=250,   home=505, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[91]=  {id=91,  name="toy tiara",                     noun={"TOY", "TIARA"},                         desc="A tiara lies here, shining with paste diamonds.",               value=63,  power=0,  weight=400,   home=55,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[92]=  {id=92,  name="gold disk",                     noun={"GOLD", "DISK"},                         desc="Strangely, there's a discarded gold tiddlywink here!",          value=63,  power=0,  weight=500,   home=61,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[93]=  {id=93,  name="pink bracelet",                 noun={"TOY", "PINK", "BRACELET"},              desc="A small pink childs bracelet has been dropped here.",           value=63,  power=0,  weight=505,   home=3,   respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[94]=  {id=94,  name="cardboard crown",               noun={"TOY", "CARDBOARD", "CROWN"},            desc="Nearby lies a cardboard crown, for kids who would be king.",    value=63,  power=0,  weight=500,   home=5,   respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[95]=  {id=95,  name="statue",                        noun={"METAL", "STATUE"},                      desc="A statue made from strange unidentifiable metal stands here.",  value=80,  power=0,  weight=500,   home=730, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[96]=  {id=96,  name="Hermit's hoard",                noun={"HOARD"},                                desc="A hoard of fabulous jewels and metals catches your gaze.",      value=350, power=0,  weight=3000,  home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[97]=  {id=97,  name="junior longsword",              noun={"JLS", "SWORD", "TOY"},                  desc="A junior longsword (for minors only) has been dropped here.",   value=63,  power=20, weight=1550,  home=41,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[98]=  {id=98,  name="wood key",                      noun={"WOOD", "KEY"},                          desc="You happen to notice a small, rather nondescript wood key.",    value=0,   power=0,  weight=5,     home=372, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[99]=  {id=99,  name="sprig of mistletoe",            noun={"MISTLETOE", "SPRIG"},                   desc="There is a small sprig of mistletoe here.",                     value=0,   power=0,  weight=50,    home=57,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[100]= {id=100, name="bejewelled dagger",             noun={"DAGGER"},                               desc="A fabulously bejewelled dagger lies before you.",               value=125, power=15, weight=100,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[101]= {id=101, name="ivory dagger",                  noun={"DAGGER", "IVORY"},                      desc="An ivory handled dagger lies before you.",                      value=125, power=15, weight=100,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[102]= {id=102, name="jet dagger",                    noun={"DAGGER", "JET"},                        desc="A dagger of darkest jet lies before you.",                      value=125, power=15, weight=100,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[103]= {id=103, name="flint dagger",                  noun={"DAGGER", "FLINT"},                      desc="An ancient flint dagger lies before you.",                      value=125, power=15, weight=100,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[104]= {id=104, name="tiepin",                        noun={"TIEPIN", "V1", "VO", "VOBJ1"},          desc="A very old coin lies on the ground",                            value=10,  power=0,  weight=100,   home=69,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[105]= {id=105, name="ornamental frog",               noun={"FROG", "V2", "VO", "VOBJ2"},            desc="A large Snowman winks at you and says \"Hi\"",                  value=50,  power=0,  weight=100,   home=22,  respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[106]= {id=106, name="fiery orb",                     noun={"FIERY", "ORB", "V3", "VO", "VOBJ3"},    desc="You see a beautiful Mist Maiden by the path",                   value=100, power=0,  weight=100,   home=419, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[107]= {id=107, name="silver spike",                  noun={"SILVER", "SPIKE", "V4", "VO", "VOBJ4"}, desc="There is a mysterious looking black bladed sword here",         value=25,  power=15, weight=100,   home=571, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[108]= {id=108, name="placebo",                       noun={"PLACEBO"},                              desc="There is a placebo here.",                                      value=0,   power=0,  weight=1,     home=144, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[109]= {id=109, name="silver spoon",                  noun={"SILVER", "SPOON"},                      desc="An old silver spoon lies before you.",                          value=80,  power=0,  weight=175,   home=662, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[110]= {id=110, name="rusty key",                     noun={"RUSTY", "KEY"},                         desc="There is a rusty key sitting here on the ground.",              value=0,   power=0,  weight=200,   home=171, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[111]= {id=111, name="amber clasp",                   noun={"AMBER", "CLASP"},                       desc="There is a beautiful amber clasp here.",                        value=100, power=0,  weight=300,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=true }, puzzles=nil, np=nil},
	[112]= {id=112, name="cheap trinket",                 noun={"CHEAP", "TRINKET"},                     desc="The dull glitter of a cheap trinket catches your eye.",         value=15,  power=0,  weight=150,   home=661, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[113]= {id=113, name="ivory bookmark",                noun={"IVORY", "BOOKMARK"},                    desc="There is a worn but still valuable bookmark here.",             value=75,  power=0,  weight=250,   home=nil, respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},
	[200]= {id=200, name="grandfather clock",             noun={"CLOCK"},                                desc="There is an old, dusty grandfather clock here.",                value=100, power=0,  weight=9000,  home=5,   respawn=nil,                  flags={ismale=true,  isplural=false, isvowel=false}, np=nil,
		puzzles = {
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) == 200 and STATE(O(200)) == 0",  -- wind clock state=0
	        effect  = "STINC(O(200)); SET_DESC(O(200),\"There is an old grandfather clock here. The dust on the dial has been disturbed.\")",
    	    psucc   = "You reach up, open the dial face and turn the winding key. Not much seems to happen.",
        	rsucc   = "$player reaches up, opens the clock dial face and turns the winding key.",
    		},
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) == 200 and STATE(ARG1) == 1",  -- wind clock state=1
	        effect  = "STINC(O(200)); SET_DESC(O(200),\"There is an old grandfather clock here, making an odd clonking sound.\")",
    	    psucc   = "You reach up and purposefully turn the winding key. The clock emits a loud clonk.",
        	rsucc   = "$player reaches up and purposefully turns the winding key. The clock emits a loud clonk.",
    		},
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) == 200 and STATE(ARG1) == 2",  -- wind clock state=1
	        effect  = "STINC(O(200)); SET_DESC(O(200),\"There is an old grandfather clock here, ticking loudly.\")",
    	    psucc   = "You reach up and carefully turn the winding key as you sense it is under tension. The clock starts tick-toking in a very satisfying manner.",
        	rsucc   = "$player reaches up and carfully turns the winding key, causing the clock to emit a rythmic tick-tock.",
    		},
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) == 200 and STATE(ARG1) == 3",  -- wind clock state=1
	        effect  = "STINC(O(200)); MOVE(O(201),LOCATE(ME()))",
    	    psucc   = "You reach up and grasp the winding key, but as you do the clock starts chiming and a small door opens in the dial.  Something falls out onto the floor!",
    		},
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) == 200",  -- We only get here if clock is fully wound
    	    psucc   = "The clock resists your attempt to wind it further, it is apparently fully wound."
		 	},
			{
	        verb    = "wind",
    	    argspec = "#",
        	test    = "IS_OBJ(ARG1) and ID(ARG1) ~= 200",  -- Fallback message if player is trying to wind something else
    	    psucc   = "I'm not sure how you would wind that!"
		 	},
		}
	},
	[201]=  {id=201, name="gold cuckoo", noun={"CUCKOO", "GOLD"}, desc="Your heart races as you espy a magnificent golden cuckoo!", value=200, power=0,  weight=1000,  home=nil, respawn=nil, flags={ismale=true,  isplural=false, isvowel=false}, puzzles=nil, np=nil},

	[800]=  {id=800, name="potion of clarity", noun={"POTION", "CLARITY"}, desc="A small vial of odd looking liquid rests delicately nearby.", value=200, power=0,  weight=100,  home=20, respawn={20}, flags={ismale=nil,  isplural=false, isvowel=false}, np=nil,
		puzzles = {
			{
	        verb    = "drink",
    	    argspec = "#",
			test    = "OWNED(ARG1) and ARG1 == O(800) and IS_CONFUSED()",
			effect  = "CLEAR_CONFUSED(); RESPAWN(ARG1)",
			psucc   = "You drink the potion and your head clears.",
			pfail   = "Nothing happens."
			},
		},
	},
	[801]=  {id=801, name="hymn of release", noun={"HYMN", "RELEASE"}, desc="There's crumpled manuscipt appearing to bear a devotional song here.", value=200, power=0,  weight=100,  home=20, respawn={20}, flags={ismale=nil,  isplural=false, isvowel=false}, np=nil,
		puzzles = {
			{
	        verb    = "chant",
    	    argspec = "#",
			test    = "OWNED(ARG1) and ARG1 == O(801) and IS_FROZEN()",
			effect  = "CLEAR_FROZEN(); RESPAWN(ARG1)",
			psucc   = "As ou chant the words of the hymn a warmth returns to your limbs.",
			pfail   = "Nothing happens."
			},
		},
	},
}
