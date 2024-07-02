
--
-- HoveyTracker
-- For ALttP Randomizers
-- Written by FxChiP
-- 
-- Note: it's not entirely complete yet; right now
-- it just parses the memory and builds a table for
-- converting to JSON (... maybe) and submitting to a
-- "backend" that will relay the results to a tracking
-- "frontend" that can automatically change numbers, light
-- items up, etc.
--
-- Apologies in advance for the wild mixture of naming/capitalization
-- conventions
--

--
-- Stock ALttP (... possibly just the Japanese version; i.e. the same one
-- you want to use the randomizer on)
-- 

-- For BizHawk, we want to read from WRAM
-- The offset they mirror into SRAM on save starts at 0x00F000
-- You can find the SRAM map (i.e. the way the data is laid out)
-- at http://alttp.run/hacking/index.php?title=SRAM_Map
-- Additionally,
-- http://alttp.run/hacking/index.php?title=Rom/Unmirrored_WRAM 
-- indicates that the working save game memory is in $7EF000...
-- That *is* a System Bus address. Which would have been useful for
-- having the event system alert us to writes, but see the 
-- main loop documentation for why we don't do that.

local MIN_OFFSET = 0x00F000

--
-- Dungeon items are a bitmap in a 16-bit int
-- Each one 16-bit int is for: compasses, big keys, and maps
-- 
-- I misread the wiki: it turns out that the areas that I had
-- marked here as "supposedly don't exist" do, of course, exist,
-- but *certain features* don't; for instance: there is a Big Key
-- to Hyrule Castle (you use it to free Zelda) but there isn't a
-- Compass.
--
-- XXX: Also I did this wrong because I'm reading the dungeon state
-- table big-endian-ly, which it's not. But it seems to have worked out
-- the same way, so...
--
local DungeonStateTable = {
	HyruleCastle = { flag = 64, idx = 1 },    -- supposedly doesn't exist
	EasternPalace = { flag = 32, idx = 2 }, -- formerly 4 actually 32 bit 5
	DesertPalace = { flag = 16, idx = 3 }, -- formerly 8 actually 16 bit 4
	Hera = { flag = 8192, idx = 10 },  -- formerly 1024 actually 8192 bit 13
	HyruleCastleAga = { flag = 8, idx = 4 },  -- supposedly doesn't exist 
	IcePalace = {flag = 16384, idx = 9 }, -- formerly 512 actually 16384 bit 14
	SkullWoods = {flag = 32768, idx = 8 }, -- formerly 256 actually 32768 bit 15
	ThievesTown = {flag = 4096, idx = 11 }, -- formerly 2048 actually 4096 bit 12
	MiseryMire = {flag = 1, idx = 7 }, -- formerly 128 actually 1 bit 0
	DarkPalace = {flag = 2, idx = 6 }, -- formerly 64 actually 2 bit 1
	SwampPalace = {flag = 4, idx = 5 }, -- formerly 32 actually 4 bit 2
	TurtleRock = {flag = 2048, idx = 12 }, -- formerly 4096 actually 2048 bit 11
	GanonsTower = {flag = 1024, idx = 13 } -- formerly 8192 actually 1024 bit 10
}

-- TODO: Quick chest count notes:
-- 0xE9CB holds the item, so 0xE9C9 and 0xE9CA hold the room number, 0x85 and 0x00 in that order (65816 is LE)
-- Turned out the room data in WRAM was in 00F10A (0x10A)
-- 
-- Chests are assigned to rooms. So the count of chests in a dungeon is the sum of all chests
-- in all rooms assigned to that dungeon. Each room may have at most 6 chests minus one key or 
-- special effect (rupee tiles). There is no easy way of knowing if a room has a spare key or
-- rupee tile thing going on. 
--

-- Item to offset table
local trackedTable = {
	bow = 0x340,
	--boomerang = 0x341,       -- see RandomExtensions
	hookshot = 0x342,
	bombs = 0x343,
	--magic_powder = 0x344,    -- see RandomExtensions
	fire_rod = 0x345,
	ice_rod = 0x346,
	swirly = 0x347,
	lightning_bolt = 0x348,
	squiggly = 0x349,
	lamp = 0x34A,
	hammer = 0x34B,
	--flute = 0x34C,           -- see RandomExtensions
	bug_net = 0x34D,
	bible = 0x34E,
	--bottles = 0x34F,         -- which bottle is selected; not a particularly important detail for us
	red_cane = 0x350,
	blue_cane = 0x351,
	magic_cape = 0x352,
	mirror = 0x353,
	gloves = 0x354,            -- as a level
	boots = 0x355,             -- but also check 0x379 for the dash ability (in theory)
	flippers = 0x356,          -- swim ability actually is granted just by having these
	moon_pearl = 0x357,
	sword = 0x359,             -- as a level
	shield = 0x35A,            -- as a level
	armor = 0x35B,             -- as a level
	first_bottle = 0x35C,      
	second_bottle = 0x35D,
	third_bottle = 0x35E,
	fourth_bottle = 0x35F,
	magic = 0x37B,
}

local trackedTableMaps = {
	bow = { "None", "EmptyBow", "Bow", "EmptySilver", "SilverArrows" },
	--boomerang = { "None", "Blue", "Red" },                 -- Rando extension; not mapping yet
	--magic_powder = { "None", "Mushroom", "MagicPowder" },  -- Rando extension; not mapping yet
	--flute = { "None", "Shovel", "Flute", "Flute" },        -- Rando extension; not mapping yet; last "Flute" is technically "Flute With Bird"
	mirror = { "None", "MagicScroll", "MagicMirror" },       -- XXX: what is MagicScroll
	shield = { "None", "BlueShield", "FireShield", "MirrorShield" },
	sword = { "None", "UncleSword", "MasterSword", "TemperedSword", "ButterSword" },
	armor = { "GreenTunic", "BlueMail", "RedMail" },        -- 0 is actually green
	first_bottle = { "None", "Mushroom", "Empty", "HealthPotion", "MagicPotion", "OmniPotion", "Fairy", "Bee", "GoldBee" }
}

-- Bottles are special: they are actually slots unto themselves, where the value "0"
-- means that bottle hasn't been acquired yet. *Empty* bottles have a value of 2. 
-- As it turns out the plain "bottle" slot is literally just the index of *which* bottle is selected.
-- Randomizers make use of a variation/extension of this pattern (having the slot point to the item to be
-- used, but allowing swapping the item in the slot point if able)
-- Here, we use the same map for the first_bottle in second, third, and fourth bottles
-- It won't ever really change, so...
trackedTableMaps.second_bottle, trackedTableMaps.third_bottle, trackedTableMaps.fourth_bottle = trackedTableMaps.first_bottle, trackedTableMaps.first_bottle, trackedTableMaps.first_bottle

--
-- Randomizer Extensions
--

-- In stock Zelda, magic powder, flute, and boomerangs, are impossible to get side by side
-- This might break some logics in randomizers (for instance: can't have powder and mushroom,
-- but need mushroom for potion shop item)
-- So they overload the 0x38C offset instead to hold flags that indicate the presence of such simultaneous items
RandoExtSlotMap = {
	[0x28] = "mushroom", -- 0x20 -> *has* mushroom, 0x08 -> *had* mushroom
	[0x10] = "magic_powder",
	[0x80] = "blue_boomerang",
	[0x40] = "red_boomerang",
	[0x04] = "shovel",
	[0x02] = "flute_dormant",
	[0x01] = "flute_active",
}

-- For randomized settings
local EntranceReqTable = { "swirly", "lightning_bolt", "squiggly" }
local DungeonRewardOrder = { 
	"EasternPalace",
	"DesertPalace",
	"???",             -- Literally doesn't get touched/used by the rando but takes up full slots for all this
	"SwampPalace",
	"DarkPalace",
	"MiseryMire",
	"SkullWoods",
	"IcePalace",
	"TowerOfHera",     -- It's interesting to me how often TowerOfHera shows up super late in these orders
	"ThievesTown",
	"TurtleRock"
}

local DungeonRewardTypeMap = {
	[0x20] = "Crystal",
	[0x37] = "GreenPendant",
	[0x38] = "BluePendant",
	[0x39] = "RedPendant"
}
local CrystalValueMap = {
	[1] = "Crystal6",       -- Crystal6 would be Misery Mire
	[2] = "Crystal1",       -- Crystal1 would be Dark Palace
	[4] = "Crystal5",       -- Crystal5 would be Ice Palace
	[8] = "Crystal7",       -- Crystal7 would be Turtle Rock
	[16] = "Crystal2",      -- Crystal2 would be Swamp Palace
	[32] = "Crystal4",      -- Crystal4 would be Thieves' Town (also called Gargoyle's Domain)
	[64] = "Crystal3"       -- Crystal3 would be Skull Woods
}

local dungeonRewards = {}
local dungeonRewardsTypes = memory.read_bytes_as_array(0xC6FE, 11, "CARTROM")
local dungeonRewardsValues = memory.read_bytes_as_array(0x1209D, 11, "CARTROM")
for i,rewardType in pairs(dungeonRewardsTypes) do
	local whichDungeon = DungeonRewardOrder[i]
	if whichDungeon ~= "???" then    -- The "???" dungeon doesn't exist, so ignore it
		if DungeonRewardTypeMap[rewardType] == "Crystal" then
			-- Crystals seem to have a reward "type" and then the value
			-- is *which* crystal they are
			-- I believe the values actually match the ones at offset 0x37A too
			local crystalValue = CrystalValueMap[dungeonRewardsValues[i]]
			dungeonRewards[whichDungeon] = crystalValue
		else
			-- Pendants' rewards types is the pendants themselves
			-- Not sure why they switched for crystals
			dungeonRewards[whichDungeon] = DungeonRewardTypeMap[rewardType]
		end
		print("debug: " .. whichDungeon .. " rewards with " .. dungeonRewards[whichDungeon])
	end
end

-- Things we need to read only once
-- They literally cannot change
local constantState = {
	medallionsEntry = {
	    TurtleRock = EntranceReqTable[memory.read_u8(0x180023, "CARTROM") + 1],
		MiseryMire = EntranceReqTable[memory.read_u8(0x180022, "CARTROM") + 1]
	},
	dungeonRewards = dungeonRewards
}

print("debug: to get into TurtleRock you need " .. constantState.medallionsEntry.TurtleRock)
print("debug: to get into MiseryMire you need " .. constantState.medallionsEntry.MiseryMire)

print("debug: hooked up callback on chest write")

local currentState = {constants = constantState}
local dungeonState = {}
memory.usememorydomain("WRAM")

while true do	
	-- So hooking into writes to the system bus was an attractive
	-- option at first -- we wouldn't have to run in a loop and
	-- do cooperative multitasking with the emulator -- but as it
	-- turns out, there are at least 4 big problems with it: 
	-- 1. You can only sign up for 8-bit-wide writes at a time,
	--    and 16-bit writes are done *frequently*. You could
	--    potentially set up one hook for the high byte and one
	--    for the low byte, have them set the same value, and last
	--    write wins, but that is so much more convoluted and hard
	--    to read that it's *probably* not worth doing.
	-- 2. The hooks, once registered, fade into the background
	--    forever, and are not trivial to remove. While this is also
	--    to an extent a *benefit* to this system, in practice if you
	--    have to reload the script, there's a somewhat unintuitive
	--    intermediate step required of removing all the functions that
	--    were hooked in, and the ambiguity of the effects of doing so
	--    (do they get garbage collected?). 
	-- 3. The set-up would end up being much less linear and much more
	--    all over the place and difficult to read even if every event
	--    we hooked into was a nice little 8-bit uint. And because we
	--    would be doing so many of them, it would *intensely* compound
	--    the #2 problem. Note that we need to keep fresh on at least 29
	--    addresses in WRAM (all the items, dungeon states) plus room datas
	--    etc.
	-- 4. Save state loads are 100% transparent unless you hook into *them*
	--    too, which would mean doing a full re-init.
	--
	-- So trust me, this way is probably better in every single way anyway.
	-- We also try to minimize the damage a bit by yielding control back to
	-- the emulator nearly every chance we get (we'd rather wait on the emulator
	-- than have the emulator wait on us).
	--

	local needUpdate = false  -- whether to update the endpoint

	-- Items
	for trackedItem, trackedOffset in pairs(trackedTable) do
		local newVal = memory.read_u8(MIN_OFFSET + trackedOffset)
		if trackedTableMaps[trackedItem] then
			newVal = trackedTableMaps[trackedItem][newVal+1]    -- Lua typically does 1-based indexing
		end

		if currentState[trackedItem] ~= newVal then
			local oldState = currentState[trackedItem]
			if oldState ~= nil then
				print("debug: " .. trackedItem .. " had: " .. currentState[trackedItem])
			else
				print("debug: " .. trackedItem .. " first track")
			end
			currentState[trackedItem] = newVal
			print("debug: "  .. trackedItem .. " got: " .. currentState[trackedItem])
			needUpdate = true
		end
		-- You'll be seeing a fair amount of emu.frameadvance()
		-- The reason is that we're actually doing a fair amount of reads
		-- But we don't need the results of all of those reads to be 100% consistent
		-- That is: two values are not reasonably going to be changing at the same time
		-- in the same frame, and we do not need a full game-state snapshot. Especially
		-- since we're running these reads *every frame* anyway, we'll definitely catch
		-- up on the changes we want to see within the *second* (or less!) anyway.
		emu.frameadvance()
	end

	--
	-- Randomizer Extended Items
	--
	local extItems = memory.read_u8(MIN_OFFSET + 0x38C)
	for itemFlag, itemName in pairs(RandoExtSlotMap) do
		--
		-- Each flag in RandoExtSlotMap that is set in the extItems uint8
		-- corresponds to an item that we have
		-- So we set these like we would any other boolean item
		-- Although I wouldn't object to, at some point, setting "slot" keys
		-- instead to list values that show what items are in the slot.
		--
		local oldState = currentState[itemName]
		if (itemFlag & extItems) ~= 0 then
			newVal = 1
		else
			newVal = 0
		end
		if newVal ~= oldState then
			currentState[itemName] = newVal
			if newVal == 1 then
			    print("debug: got rando extended item " .. itemName)
			else
				print("debug: lost rando extended item " .. itemName)
			end
			needUpdate = true
		end
	end
	emu.frameadvance()

	-- Dungeon treats
	local compasses = memory.read_u16_be(MIN_OFFSET + 0x364)
	local bigKeys = memory.read_u16_be(MIN_OFFSET + 0x366)
	local maps = memory.read_u16_be(MIN_OFFSET + 0x368)
	local keyCounts = memory.read_bytes_as_array(MIN_OFFSET + 0x37D, 13)
	for dungeon, dungeonInfo in pairs(DungeonStateTable) do
		local hasBigKey, hasCompass, hasMap = (bigKeys & dungeonInfo.flag), (compasses & dungeonInfo.flag), (maps & dungeonInfo.flag)
		keysCount = keyCounts[dungeonInfo.idx]
		if not dungeonState[dungeon] 
		   or dungeonState[dungeon].hasBigKey ~= hasBigKey 
		   or dungeonState[dungeon].hasCompass ~= hasCompass 
		   or dungeonState[dungeon].hasMap ~= hasMap 
		   or dungeonState[dungeon].keyCount ~= keysCount then
			if not dungeonState[dungeon] then
				print("debug: " .. dungeon .. " first track")
			else
				print("debug: " .. dungeon .. " had: key? " .. dungeonState[dungeon].hasBigKey .. " compass? " .. dungeonState[dungeon].hasCompass .. " map? " .. dungeonState[dungeon].hasMap .. " key count? " .. dungeonState[dungeon].keyCount)
			end
			dungeonState[dungeon] = {
			    hasBigKey = hasBigKey,
			    hasCompass = hasCompass,
			    hasMap = hasMap,
			    keyCount = keysCount
			}
			print("debug: " .. dungeon .. " now has: key? " .. dungeonState[dungeon].hasBigKey .. " compass? " .. dungeonState[dungeon].hasCompass .. " map? " .. dungeonState[dungeon].hasMap .. " keys count? " .. dungeonState[dungeon].keyCount)
			needUpdate = true
		end
		emu.frameadvance()
	end
	currentState.dungeons = dungeonState

	-- Progression
	-- TODO: put this into currentState... heh
	local pendants, crystals = memory.read_u8(MIN_OFFSET + 0x374), memory.read_u8(MIN_OFFSET + 0x37A)

	-- Update phase
	if needUpdate then
		-- XXX: do actual submit logic later
		print("debug: would submit")
	end
	emu.frameadvance()
end
