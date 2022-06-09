# UGC Block

User Generated Content (UGC) can become a concern for server owners if bad actors decide to show up.

This can include bad language in chat, on items names and item descriptions as well has NSFW / illegal imagery for custom decals and sprays.

### Features

* Restrict usage of sprays, jingles (TF2: decals, item names and descriptions) based on TrustFactor
* Log files uploaded from clients
* Scan uploaded files for fake AV triggers (and ban on detection)
* Ingame commands to forward and backwards look-up of filenames for a players spray/jingle
* Late download sprays if initially blocked due to permission granted later

### Config

This plugin allows you to control when players are able to use custom decals, item names, descriptions and sprays through the following convars.

`sm_ugc_disable_decal "0"`   
Always block items with custom decals

`sm_ugc_disable_description "0"`   
Always block items with custom descriptions

`sm_ugc_disable_name "0"`   
Always block items with custom names

`sm_ugc_disable_spray "0"`   
Always block players from using sprays

`sm_ugc_disable_jingle "0"`   
Always block players from using jingles ('sound sprays')

`sm_ugc_trust_decal "*3"`   
TrustFlags required to allow items with custom decals, empty to always allow

`sm_ugc_trust_description "*3"`   
TrustFlags required to allow items with custom descriptions, empty to always allow

`sm_ugc_trust_name "*3"`   
TrustFlags required to allow items with custom names, empty to always allow

`sm_ugc_trust_spray "*3"`   
TrustFlags required to allow sprays, empty to always allow

`sm_ugc_trust_jingle "*3"`   
TrustFlags required to allow jingles, empty to always allow

`sm_ugc_log_uploads "1"`   
Log all client file uploads to `user_custom_received.log`

**Some malicious spray files were used to trip false positives in client anti-virus**   
[Spray Exploit Fixer](https://forums.alliedmods.net/showthread.php?t=323447) catches this and I recommend you use that plugin.

Items that do not pass the filters will currently just be removed from the player.   
In case of weapons i might look into using TF2 Gimme or TF2 Items to generate and re-equip "clean" versions.

User custom files will still upload to the server, but the download is limited:   
If a client connects while a spray or jingle is blocked, that file should no longer download to other clients.
In case sprays or jingles get blocked after they join, no new clients will receive the files, and the action should
be blocked from being executed.
Getting permission to use sprays or jingles after being in the server for some seconds will *not* send the files
to other clients. The player should reconnect in this case to trigger the download.

### Commands

The logs can also be checked directly from the server with the command `sm_ugclookup` or `sm_ugclookuplogs`.
Both commands require the Kick flag by default and the former tried to check online players first.

Arguments is a player name, SteamID or a filename. If an online player is found, it will return their current
spray and jingle file as well as the types of UGC they can currently use. Otherwise the log will be scanned through
and the last up to 50 entries will be dumped to your console, including the timestamp.

### Dependencies

While this plugin was originally written for TF2, I should have changed it to work on other games as well.
As a result dependencies that do not apply to your game should only be required for compilation.

* This plugin requires [TF2 Attributes](https://github.com/nosoop/tf2attributes) to check if an items has a custom name/description/decal.   
  I'm using nosoops fork, but FlamingSarges original might work as well. In any case Version 1.3.2 or above is required.
* [TrustFactor](https://github.com/DosMike/SM-TrustFactor) is required to check players trustworthiness.

* For late downloading / invisible spray fix install one of these (optional). While FNM is more geared towards single player transfers, both
  plugins seem fit for the job, and should work. Without this, it might take a map change after another player joins before they receive that
  players spray/jingle file.
  * [FileNetMessage](https://forums.alliedmods.net/showthread.php?t=233549)
  * [LateDL](https://forums.alliedmods.net/showthread.php?t=305153)