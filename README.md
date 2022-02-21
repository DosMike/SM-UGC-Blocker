# UGC Block

User Generated Content (UGC) can become a concern for server owners if bad actors decide to show up.

This can include bad language in chat, on items names and item descriptions as well has NSFW / illegal imagery for custom decals and sprays.

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

Items that do not pass the filters will currently just be removed from the player.   
In case of weapons i might look into using TF2 Gimme or TF2 Items to generate and re-equip "clean" versions.

User custom files will still upload to the server, but the download is limited:   
If a client connects while a spray or jingle is blocked, that file should no longer download to other clients.
In case sprays or jingles get blocked after they join, no new clients will receive the files, and the action should
be blocked from being executed.
Getting permission to use sprays or jingles after being in the server for some seconds will *not* send the files
to other clients. The player should reconnect in this case to trigger the download.

## Dependencies

* This plugin requires [TF2 Attributes](https://github.com/nosoop/tf2attributes) to check if an items has a custom name/description/decal.   
  I'm using nosoops fork, but FlamingSarges original might work as well. In any case Version 1.3.2 or above is required.
* [TrustFactor](https://github.com/DosMike/SM-TrustFactor) is required to check players trustworthiness.
