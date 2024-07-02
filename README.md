# HoveyTracker

An open source ALttP auto-tracker.

NOTE: The Lua half is still a little unfinished and, for now, prints out debug messages about the current game state. **THIS INCLUDES SPOILERS.** Specifically, it will spoil (1) what rewards each dungeon has (i.e. Crystal or Pendant) and (2) what the entrance requirement medallions for Misery Mire and Turtle Rock are.

These are the files for the data-loading portions -- the Lua script that exports the game state and the PHP script that takes it in and reports it to the frontend. Currently the only frontend for this system is [my fork](https://github.com/fxchip/alttprandotracker) of [crossproduct's](https://twitch.tv/crossproduct) [alttprandotracker](https://github.com/crossproduct/alttprandotracker), but I would definitely encourage rolling your own (or asking crossproduct/HalfARebel on [their Discord](https://discord.gg/a7Nk5KV)). 

# Usage

1. Upload the php/ files to your favorite PHP-supporting webhost in the subdirectory of your choice. I use [DreamHost](https://dreamhost.com).
2. Upload [my fork of alttprandotracker](https://github.com/fxchip/alttprandotracker) as well. (Make sure it points to the right place at your host!)
3. Fix the configuration section in bizhawk-lua/hoveytrack.lua to go to the HTTP URL where you can reach the files at #1. (This step isn't done being implemented yet)
4. Load the bizhawk-lua/hoveytrack.lua into BizHawk using the Lua console.
5. Run your randomizer!

# Why the name?

The tracker was written for [kjhovey](https://twitch.tv/kjhovey) (and for fun).

