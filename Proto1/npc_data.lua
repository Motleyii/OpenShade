----------------------------------------------------------------------
-- npc_data.lua
-- NPC prototype and spawn definitions
--
-- Expected by npc_loader.lua:
--   return {
--     prototypes = { [id] = prototype_table, ... },
--     spawns     = {
--        { proto_id=?, room=? },
--        ...
--     }
--   }
----------------------------------------------------------------------

--NPC path is the sequential locations that the NPC visits, wraping to beginning
--NPC's move at different speeds, but I don't have info on how fast.
--The speed field is supposed to indicate number of seconds that the NPC waits in a location before moving

return {
	prototypes = {
		[0]=  {npc=0,  name="NPC0",    power=1,    stamina=1,     value=1,    speed=10, enters="NPC0",                                                         exits="NCP0",                                                        here="NCP0",                                                    path = {0}},
		[1]=  {npc=1,  name="bear",    power=16,   stamina=275,   value=125,  speed=15, enters="A huge grizzly bear pads along.",                              exits="The bear wanders off, snuffling loudly as it does so.",       here="A bear with big, doleful eyes snuffles nearby.",          path = {138, 134, 132, 136, 138, 134, 133, 136, 137, 133, 132, 137}},
		[2]=  {npc=2,  name="beggar",  power=20,   stamina=300,   value=150,  speed=10, enters="A beggar limps in, holding a begging bowl before him.",        exits="The beggar shuffles slowly out, his rags trailing behind...", here="A beggar watches you, a crafty gleam in his eyes…",       path = {168, 170, 172, 151, 152, 163, 162, 167}},
		[3]=  {npc=3,  name="crow",    power=5,    stamina=100,   value=50,   speed=50, enters="A malevolent black crow flaps in, crying \"corpse, corpse\".", exits="The black crow flaps out in search of carrion.",              here="A crow flaps towards you, striking at your eyes!",        path = {22, 5, 536, 537, 98, 96, 94, 92, 93, 536, 537, 2, 3, 4}},
		[4]=  {npc=4,  name="death",   power=18,   stamina=300,   value=145,  speed=15, enters="Death strides in, carrying a long scythe... ",                 exits="Death decides not to kill you and leaves.",                   here="You sense a deathly presence here....",                   path = {559, 563, 559, 558, 559, 555}},
		[5]=  {npc=5,  name="deer",    power=8,    stamina=100,   value=50,   speed=50, enters="A large red deer stalks in.",                                  exits="The deer stalks gracefully away.",                            here="A deer grazes nearby.",                                   path = {126, 127, 121, 57, 55, 6, 55, 57, 122, 123, 124, 125}},
		[6]=  {npc=6,  name="dwarf",   power=20,   stamina=140,   value=70,   speed=70, enters="A dwarf housekeeper stumps in.",                               exits="The dwarf housekeeper stumps out.",                           here="The dwarf housekeeper eyes you with suspicion.",          path = {500, 504, 501, 503, 508, 509, 510, 511, 512, 513, 497, 494, 491, 489, 492, 495, 498, 502, 506, 499, 505}},
		[7]=  {npc=7,  name="ghost",   power=5,    stamina=125,   value=75,   speed=75, enters="A ghost glides in, moaning horribly!",                         exits="The ghost glides out..",                                      here="A ghost floats before you!",                              path = {44, 47, 45, 44, 43, 42, 43}},
		[8]=  {npc=8,  name="girl",    power=1000, stamina=1000,  value=1000, speed=10, enters="The Strange Little Girl drifts in..",                          exits="The Strange Little Girl drifts out..",                        here="The Strange Little Girl is standing nearby.",             path = {139, 138, 137, 134, 133, 132, 131, 130, 129, 128, 127, 125, 124, 40, 21, 13, 415, 414, 6, 7, 8, 53, 49, 54, 61, 71, 72, 73}},
		[9]=  {npc=9,  name="guard",   power=8,    stamina=350,   value=80,   speed=80, enters="A burly guard strides in.",                                    exits="The guard strides out.",                                      here="A guard stands rigidly to attention near you.",           path = {8, 53, 49, 54, 61, 62, 61, 54, 6, 7, 8, 9, 10, 9}},
		[10]= {npc=10, name="hermit",  power=18,   stamina=400,   value=70,   speed=70, enters="The hermit stamps angrily in.",                                exits="The hermit glares angrily at you before stamping out.",       here="The hermit looks at you with evident distaste.",          path = {754, 752, 753, 752, 754, 761, 755, 761, 755, 756, 757, 755}},
		[11]= {npc=11, name="hound",   power=8,    stamina=130,   value=60,   speed=60, enters="DOES NOT MOVE",                                                exits="DOES NOT MOVE",                                               here="The hound of San Simeon guards the stairs.",              path = {503}},
		[12]= {npc=12, name="leech",   power=40,   stamina=50000, value=100,  speed=10, enters="You feel a light, slimy touch caress your legs...",            exits="Something slimy kisses your legs and drifts away…",           here="Occasional dark shapes slither through the water.",       path = {748, 742, 743, 744, 745, 746, 747}},
		[13]= {npc=13, name="lion",    power=20,   stamina=275,   value=80,   speed=80, enters="An enormous lion pads in, head swinging from side to side.",   exits="The lion decides to ignore you and pads out.",                here="A lion idly watchs you, wondering what you taste like.",  path = {406, 401, 402, 403, 404, 406, 401, 402, 404, 406, 402, 403, 404, 405, 401, 402, 403, 405}},
		[14]= {npc=14, name="lioness", power=20,   stamina=350,   value=80,   speed=80, enters="A lioness prowls in, looking dangerously hungry.",             exits="The lioness wonders where her cub has got to and leaves.",    here="A magnificent lioness eyes you up, licking her lips.",    path = {394, 399, 393, 394, 395, 409, 393}},
		[15]= {npc=15, name="morloch", power=20,   stamina=300,   value=170,  speed=17, enters="The Morloch shuffles in, bulbous eyes glowing evilly!",        exits="The Morloch peers about, then shuffles away.",                here="The huge eyes of an evil Morloch stare intently at you.", path = {385, 387, 371, 370, 368, 367, 374, 377, 378, 383, 378, 384, 379, 380}},
		[16]= {npc=16, name="mouse",   power=15,   stamina=225,   value=65,   speed=65, enters="A mouse scampers in, whiskers twiching nervously.",            exits="The mouse scurries out, nose to the ground.",                 here="A mouse scurries about in search of anything edible.",    path = {62, 61, 71, 72, 74, 82, 64, 63}},
		[17]= {npc=17, name="sprite",  power=15,   stamina=30,    value=50,   speed=50, enters="DOES NOT MOVE",                                                exits="DOES NOT MOVE",                                               here="A tree sprite dances a merry jig before you.",            path = {130}},
		[18]= {npc=18, name="thief",   power=12,   stamina=300,   value=80,   speed=80, enters="The thief slinks in, carrying a bag over one shoulder.",       exits="The thief sidles into the shadows, and is gone.",             here="A thief lurks near, with evil intent on his face.",       path = {54, 4, 13, 82, 182, 171, 169, 8, 10, 54, 13, 104, 82, 171, 169, 479, 10}},
		[20]= {npc=20, name="wraith",  power=30,   stamina=200,   value=125,  speed=12, enters="A wraith of doom floats in.",                                  exits="The wraith of doom wails evilly and floats out.",             here="A wraith hangs evilly in the air.",                       path = {455, 459, 460, 459, 457, 458, 454, 455, 459, 460, 459, 457, 458, 454, 456, 459, 460, 456, 457, 458, 454, 456, 459, 456, 457, 458, 454, 456, 459}},
		[21]= {npc=21, name="zombie",  power=12,   stamina=666,   value=350,  speed=35, enters="A decaying Zombie shuffles slowly in.",                        exits="The rotting Zombie slowly shuffles out.",                     here="The rotting figure of a Zombie stares blankly at you.",   path = {728, 729, 730, 729, 728, 727, 724, 725, 763, 764, 765, 731, 765, 726, 725, 724, 727}},
	},
	
	spawns = {
		{proto_id = 1,  room = 138},
		{proto_id = 2,  room = 168},
		{proto_id = 3,  room = 22},
		{proto_id = 4,  room = 559},
		{proto_id = 5,  room = 126},
		{proto_id = 6,  room = 500},
		{proto_id = 7,  room = 44},
		{proto_id = 8,  room = 139},
		{proto_id = 9,  room = 8},
		{proto_id = 10, room = 754},
		{proto_id = 11, room = 503},
		{proto_id = 12, room = 748},
		{proto_id = 13, room = 406},
		{proto_id = 14, room = 394},
		{proto_id = 15, room = 385},
		{proto_id = 16, room = 62},
		{proto_id = 17, room = 130},
		{proto_id = 18, room = 54},
		{proto_id = 20, room = 455},
		{proto_id = 21, room = 728},
	}
}
