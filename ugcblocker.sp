#include <sourcemod>
#include <sdkhooks>
#include <regex>

#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <tf_econ_data>
#include <tf2utils>
#include <tf2attributes>
#include "sourcebanspp.inc"
#tryinclude <trustfactor>
#define REQUIRE_PLUGIN

#if !defined _trustfactor_included
#warning You are compiling without TrustFactors - Some functionallity will be missing!
#define PLUGIN_VERSION "25w21a NTF"
#else
#define PLUGIN_VERSION "25w21a"
#endif

#pragma newdecls required
#pragma semicolon 1

#define UGC_LOGFILE "user_generated_content.log"

enum eUserGeneratedContent {
	ugcNone=0,
	ugcSpray=1,
	ugcJingle=2, //this is an audatory version of sprays: wav @44.1kHz, max 512KiB
	ugcDecal=4,
	ugcName=8,
	ugcDescription=16,
}

enum struct FileRequestData {
	int target;
	int source;
	eUserGeneratedContent sourceType;
}

static bool clientUGCloaded[MAXPLAYERS+1]; //did we load ugc flags?
static eUserGeneratedContent clientUGC[MAXPLAYERS+1]; //green-light flags for trusted
static eUserGeneratedContent checkUGCTypes; //we only care to check those
static char clientSprayFile[MAXPLAYERS+1][128];
static char clientJingleFile[MAXPLAYERS+1][128];
static ArrayList fileUploadScanQueue; //files that were just uploaded and need to be scanned
static bool clientNotifiedGrants[MAXPLAYERS+1]; //did we tell the player what they can do?

static ConVar cvar_disable_Spray;
static ConVar cvar_disable_Jingle;
static ConVar cvar_disable_Decal;
static ConVar cvar_disable_Name;
static ConVar cvar_disable_Description;
static eUserGeneratedContent blockUGCTypes; //these are always blocked

#if defined _trustfactor_included
static ConVar cvar_trust_Spray;
static ConVar cvar_trust_Jingle;
static ConVar cvar_trust_Decal;
static ConVar cvar_trust_Name;
static ConVar cvar_trust_Description;
static TrustCondition trust_Spray;
static TrustCondition trust_Jingle;
static TrustCondition trust_Decal;
static TrustCondition trust_Name;
static TrustCondition trust_Description;
#endif
static bool bConVarUpdates; //allow user flag updates from convar changes, disabled in plugin start

static ConVar cvar_logUploads;
static bool bLogUserCustomUploads;
//this is used to reduce the amount of log entries, but because i can't waste arbitrary amounts of memory
//i will clear this map every map. entries are "accountidhex_customtexturehex" -> 1 (so used as hash set)
static StringMap accountCustomTextures;

public Plugin myinfo = {
	name = "UGC Blocker",
	author = "reBane",
	description = "Block User Generated Content (Sprays Jingles and Items)",
	version = PLUGIN_VERSION,
	url = "N/A"
}

void HookAndLoad(ConVar cvar, ConVarChanged handler) {
	char def[256], val[256];
	cvar.AddChangeHook(handler);
	cvar.GetDefault(def, sizeof(def));
	cvar.GetString(val, sizeof(val));
	Call_StartFunction(INVALID_HANDLE, handler);
	Call_PushCell(cvar);
	Call_PushString(def);
	Call_PushString(val);
	Call_Finish();
}
public void LockConVar(ConVar convar, const char[] oldValue, const char[] newValue) {
	char def[64];
	if (GetPluginInfo(INVALID_HANDLE, PlInfo_Version, def, sizeof(def)) && !StrEqual(def, newValue)) convar.SetString(def,_,true);
}

public void OnPluginStart() {

	LoadTranslations("common.phrases");

	ConVar version = CreateConVar("sm_ugcblocker_version", PLUGIN_VERSION, _, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	HookAndLoad(version, LockConVar);
	delete version;

	cvar_disable_Spray = CreateConVar("sm_ugc_disable_spray", "0", "Always block players from using sprays", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
	HookAndLoad(cvar_disable_Spray, OnCvarChange_DisableSpray);

	cvar_disable_Jingle = CreateConVar("sm_ugc_disable_jingle", "0", "Always block players from using jingles ('sound sprays')", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
	HookAndLoad(cvar_disable_Jingle, OnCvarChange_DisableJingle);

	if (GetEngineVersion() == Engine_TF2) {
		cvar_disable_Decal = CreateConVar("sm_ugc_disable_decal", "0", "Always block items with custom decals", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
		HookAndLoad(cvar_disable_Decal, OnCvarChange_DisableDecal);

		cvar_disable_Name = CreateConVar("sm_ugc_disable_name", "0", "Always block items with custom names", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
		HookAndLoad(cvar_disable_Name, OnCvarChange_DisableName);

		cvar_disable_Description = CreateConVar("sm_ugc_disable_description", "0", "Always block items with custom descriptions", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
		HookAndLoad(cvar_disable_Description, OnCvarChange_DisableDescription);
	}

#if defined _trustfactor_included
	cvar_trust_Spray = CreateConVar("sm_ugc_trust_spray", "*3", "TrustFlags required to allow sprays, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED);
	HookAndLoad(cvar_trust_Spray, OnCvarChange_TrustSpray);

	cvar_trust_Jingle = CreateConVar("sm_ugc_trust_jingle", "*3", "TrustFlags required to allow jingles, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED);
	HookAndLoad(cvar_trust_Jingle, OnCvarChange_TrustJingle);

	if (GetEngineVersion() == Engine_TF2) {
		cvar_trust_Decal = CreateConVar("sm_ugc_trust_decal", "*3", "TrustFlags required to allow items with custom decals, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED);
		HookAndLoad(cvar_trust_Decal, OnCvarChange_TrustDecal);

		cvar_trust_Name = CreateConVar("sm_ugc_trust_name", "*3", "TrustFlags required to allow items with custom names, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED);
		HookAndLoad(cvar_trust_Name, OnCvarChange_TrustName);

		cvar_trust_Description = CreateConVar("sm_ugc_trust_description", "*3", "TrustFlags required to allow items with custom descriptions, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED);
		HookAndLoad(cvar_trust_Description, OnCvarChange_TrustDescription);
	}
#else
	// if trustfactors is missing, always check agains disabled flags
	checkUGCTypes = ugcSpray|ugcJingle;
	if (GetEngineVersion() == Engine_TF2)
		checkUGCTypes |= ugcDecal|ugcName|ugcDescription;
#endif

	cvar_logUploads = CreateConVar("sm_ugc_log_uploads", "1", "Log all client file uploads to user_custom_received.log", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
	HookAndLoad(cvar_logUploads, OnCvarChange_LogUploads);

	AutoExecConfig();
	bConVarUpdates=true;

	accountCustomTextures = new StringMap();

	AddTempEntHook("Player Decal", OnTempEnt_PlayerDecal);
	if (GetEngineVersion() == Engine_TF2) {
		HookEvent("post_inventory_application", OnEvent_ClientInventoryRegeneratePost, EventHookMode_Pre);
	} //for other games we use the spawn post sdkhook

	UpdateAllowedUGCAll();

	RegAdminCmd("sm_ugclookup", Command_LookupFile, ADMFLAG_KICK, "Usage: sm_ugclookup <userid|name|steamid|filename> - Lookup ugc filenames <-> SteamIDs. Return online players if any match, scan though log otherwise");
	RegAdminCmd("sm_ugclookuplogs", Command_LookupFile, ADMFLAG_KICK, "Usage: sm_ugclookuplogs <name|steamid|filename> - Lookup ugc filenames <-> SteamIDs. Scan log files directly");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");

	RegAdminCmd("untrustmyspray", Command_Untrustme, ADMFLAG_KICK, "");
}

public void OnPluginEnd() {
	delete fileUploadScanQueue;
}


public void OnCvarChange_DisableSpray(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcSpray; else blockUGCTypes &=~ ugcSpray;
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_DisableJingle(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcJingle; else blockUGCTypes &=~ ugcJingle;
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_DisableDecal(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcDecal; else blockUGCTypes &=~ ugcDecal;
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_DisableName(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcName; else blockUGCTypes &=~ ugcName;
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_DisableDescription(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcDescription; else blockUGCTypes &=~ ugcDescription;
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
#if defined _trustfactor_included
public void OnCvarChange_TrustSpray(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcSpray;
		trust_Spray.Always();
	} else {
		checkUGCTypes |= ugcSpray;
		trust_Spray.Parse(val);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustJingle(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcJingle;
		trust_Jingle.Always();
	} else {
		checkUGCTypes |= ugcJingle;
		trust_Jingle.Parse(val);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustDecal(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcDecal;
		trust_Decal.Always();
	} else {
		checkUGCTypes |= ugcDecal;
		trust_Decal.Parse(val);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustName(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcName;
		trust_Name.Always();
	} else {
		checkUGCTypes |= ugcName;
		trust_Name.Parse(val);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustDescription(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcDescription;
		trust_Description.Always();
	} else {
		checkUGCTypes |= ugcDescription;
		trust_Description.Parse(val);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
#endif
public void OnCvarChange_LogUploads(ConVar convar, const char[] oldValue, const char[] newValue) {
	bLogUserCustomUploads = convar.BoolValue;
}


// ===== Ok, boilerplate is over =====

public Action Command_LookupFile(int client, int args) {
	if (GetCmdArgs() < 1) {
		ReplyToCommand(client, "Requires a name, userid, steamid or (partial) filename");
		return Plugin_Handled;
	}
	char target[64];
	bool forcedLogs;
	GetCmdArg(0, target, sizeof(target));
	if (StrContains(target, "log", false)>0) forcedLogs=true;

	GetCmdArgString(target, sizeof(target));
	int online = FindTarget(client, target, true, false);
	if (!forcedLogs && online > 0) {
		ReplyToCommand(client, "[UGC] Player '%L'", online);
		if (clientSprayFile[online][0]) ReplyToCommand(client, "[UGC] > Spray: %s", clientSprayFile[online]);
		else ReplyToCommand(client, "[UGC] > No Spray received");
		if (clientJingleFile[online][0]) ReplyToCommand(client, "[UGC] > Jingle: %s", clientJingleFile[online]);
		else ReplyToCommand(client, "[UGC] > No Jingle received");
		UGCFlagString(clientUGC[online], target, sizeof(target));
		ReplyToCommand(client, "[UGC] Has permission to %s", target);
	} else {
		File log = OpenFile(UGC_LOGFILE, "rt");
		if (log == INVALID_HANDLE) {
			ReplyToCommand(client, "[UGC] Logs not found");
		} else {
			Regex entryUpload = new Regex("^L ([\\w\\/]+ - [0-9:]+): Linked User File user_custom(.*) to (.*)<[0-9]+><(.*)><(?:Console)?>$", PCRE_UTF8|PCRE_CASELESS);
			Regex entrySteam = new Regex("^L ([\\w\\/]+ - [0-9:]+): Custom Texture (\\w+) on ItemDef [0-9]+ \\(\\w+\\) from (.*)<[0-9]+><(.*)><(?:Console)?>$", PCRE_UTF8|PCRE_CASELESS);
			char line[256];
			char matchTime[32], matchFile[32], matchName[64], matchSteamID[64];
			ArrayList hits = new ArrayList(ByteCountToCells(256));
			while (log.ReadLine(line, sizeof(line))) {
				if (entryUpload.Match(line)>0) {
					entryUpload.GetSubString(1, matchTime, sizeof(matchTime));
					entryUpload.GetSubString(2, matchFile, sizeof(matchFile));
					entryUpload.GetSubString(3, matchName, sizeof(matchName));
					entryUpload.GetSubString(4, matchSteamID, sizeof(matchSteamID));

					if (StrContains(matchSteamID, target, false)>=0 || StrContains(matchName, target, false)>=0 || StrContains(matchFile, target, false)>=0) {
						Format(line, sizeof(line), " %s  %s<%s>  at %s", matchFile, matchName, matchSteamID, matchTime);
						hits.PushString(line);
					}
				} else if (entrySteam.Match(line)>0) {
					entrySteam.GetSubString(1, matchTime, sizeof(matchTime));
					entrySteam.GetSubString(2, matchFile, sizeof(matchFile));
					entrySteam.GetSubString(3, matchName, sizeof(matchName));
					entrySteam.GetSubString(4, matchSteamID, sizeof(matchSteamID));

					if (StrContains(matchSteamID, target, false)>=0 || StrContains(matchName, target, false)>=0 || StrContains(matchFile, target, false)>=0) {
						Format(line, sizeof(line), " UGCHandle %s  %s<%s>  at %s", matchFile, matchName, matchSteamID, matchTime);
						hits.PushString(line);
					}
				}
			}
			delete log;
			delete entryUpload;
			delete entrySteam;
			if (hits.Length==0) {
				ReplyToCommand(client, "[UGC] No hits for target %s", target);
			} else {
				bool restoreToChat;
				if (GetCmdReplySource() == SM_REPLY_TO_CHAT) {
					ReplyToCommand(client, "[UGC] Check console for output");
					SetCmdReplySource(SM_REPLY_TO_CONSOLE);
					restoreToChat = true;
				}
				ReplyToCommand(client, "[UGC] Last %i logged hits for target %s", hits.Length>50?50:hits.Length, target);
				for (int i=1,back=hits.Length-1;i<=50 && back>=0;i+=1,back-=1) {
					hits.GetString(back, line, sizeof(line));
					ReplyToCommand(client, " %2i %s", i, line);
				}
				if (restoreToChat) {
					SetCmdReplySource(SM_REPLY_TO_CHAT);
				}
			}
			delete hits;
		}
	}
	return Plugin_Handled;
}

public Action Command_Untrustme(int client, int args) {
	clientUGC[client] &= ~ugcSpray;
	ReplyToCommand(client, "You can no longer spray");
	return Plugin_Handled;
}

public Action Command_Say(int client, const char[] command, int argc) {
	char message[128];
	GetCmdArgString(message, sizeof(message));
	if (!( (StrContains(message, "why can", false)>=0 || StrContains(message, "when can", false)>=0 || StrContains(message, "blocked", false)>=0 || StrContains(message, "disabled", false)>=0 || StrContains(message, "not allowed", false)>=0) &&
			(StrContains(message, " i ", false)>=0 || StrContains(message, " my ", false)>=0 || StrContains(message, " is ", false)>=0 || StrContains(message, "are ", false)>=0) )) {// can also allows for can't
		return Plugin_Continue; //not directed to us
	}

	if (StrContains(message, "spray", false)>=0) {
		if (blockUGCTypes & ugcSpray)
			PrintToChat(client, "> Sprays are DISABLED");
#if defined _trustfactor_included
		else if (trust_Spray.required || trust_Spray.optional)
			PrintTrustConditionReadable(client, trust_Spray, "> Sprays need ");
#endif
		else
			PrintToChat(client, "> Sprays are ALLOWED");
	}
	if (StrContains(message, "jingle", false)>=0) {
		if (blockUGCTypes & ugcJingle)
			PrintToChat(client, "> Jingles are DISABLED");
#if defined _trustfactor_included
		else if (trust_Jingle.required || trust_Jingle.optional)
			PrintTrustConditionReadable(client, trust_Jingle, "> Jingles need ");
#endif
		else
			PrintToChat(client, "> Jingles are ALLOWED");
	}
	if (GetEngineVersion() == Engine_TF2) {
		if (StrContains(message, "decal", false)>=0) {
			if (blockUGCTypes & ugcDecal)
				PrintToChat(client, "> Decals are DISABLED");
#if defined _trustfactor_included
			else if (trust_Decal.required || trust_Decal.optional)
				PrintTrustConditionReadable(client, trust_Decal, "> Decals need ");
#endif
			else
				PrintToChat(client, "> Decals are ALLOWED");
		}
		if (StrContains(message, "name", false)>=0) {
			if (blockUGCTypes & ugcName)
				PrintToChat(client, "> Naming Items is DISABLED");
#if defined _trustfactor_included
			else if (trust_Name.required || trust_Name.optional)
				PrintTrustConditionReadable(client, trust_Name, "> NameTags need ");
#endif
			else
				PrintToChat(client, "> Named Items are ALLOWED");
		}
		if (StrContains(message, "desc", false)>=0) {
			if (blockUGCTypes & ugcDescription)
				PrintToChat(client, "> Item Descriptions are DISABLED");
#if defined _trustfactor_included
			else if (trust_Description.required || trust_Description.optional)
				PrintTrustConditionReadable(client, trust_Description, "> Descriptions need ");
#endif
			else
				PrintToChat(client, "> Descriptions are ALLOWED");
		}
	}
	return Plugin_Continue;
}
#if defined _trustfactor_included
static void PrintTrustConditionReadable(int client, TrustCondition condition, const char[] prefix) {
	TrustFactors trust = GetClientTrustFactors(client);
	TrustFactors missing = (condition.required|condition.optional) &~ trust;
	int optionalGranted;
	for (int bits = view_as<int>(trust & condition.optional); bits; bits >>= 1) if (bits&1) optionalGranted++;
	char buffer[512];
	char word[32];
	if (condition.required) {
		bool wasGreen, wantGreen;
		for (TrustFactors f = TrustPlaytime; f <= TrustNotEconomyBanned; f <<= view_as<TrustFactors>(1)) {
			if (condition.required & f) {
				//save bytes in message by keepin track of this
				wantGreen = !(missing&f);
				if (wasGreen!=wantGreen) {
					if (wantGreen) StrCat(buffer, sizeof(buffer), "\x04");
					else StrCat(buffer, sizeof(buffer), "\x04");
					wasGreen=wantGreen;
				}
				//append name
				GetTrustFactorName(f, word, sizeof(word));
				Format(buffer, sizeof(buffer), "%s%s, ", buffer, word);
			}
		}
		//remove last comma
		buffer[strlen(buffer)-2]=0;
		//optional concat
		if (condition.optionalCount) {
			Format(buffer, sizeof(buffer), "%s\x01 and ", buffer);
		}
	}
	if (condition.optionalCount) {
		bool wasGreen, wantGreen;
		Format(buffer, sizeof(buffer), "%s%i of ", buffer, condition.optionalCount);
		for (TrustFactors f = TrustPlaytime; f <= TrustNotEconomyBanned; f <<= view_as<TrustFactors>(1)) {
			if (condition.optional & f) {
				//save bytes in message by keepin track of this
				wantGreen = !(missing&f);
				if (wasGreen!=wantGreen) {
					if (wantGreen) StrCat(buffer, sizeof(buffer), "\x04");
					else StrCat(buffer, sizeof(buffer), "\x04");
					wasGreen=wantGreen;
				}
				//append name
				GetTrustFactorName(f, word, sizeof(word));
				Format(buffer, sizeof(buffer), "%s%c%s, ", buffer, (missing&f)?1:4,word);
			}
		}
	}
	//remove last comma
	buffer[strlen(buffer)-2]=0;
	PrintToChat(client, "\x01%s%s", prefix, buffer);
}
static void GetTrustFactorName(TrustFactors factor, char[] namebuf, int size) {
	switch(factor) {
		case TrustPlaytime: strcopy(namebuf, size, "Playtime");
		case TrustPremium: strcopy(namebuf, size, "Not F2P");
		case TrustDonorFlag: strcopy(namebuf, size, "Donator");
		case TrustCProfilePublic: strcopy(namebuf, size, "Public Profile");
		case TrustCProfileSetup: strcopy(namebuf, size, "Setup Profile");
		case TrustCProfileLevel: strcopy(namebuf, size, "Steam Level");
		case TrustCProfileGametime: strcopy(namebuf, size, "Total Gametime");
		case TrustCProfileAge: strcopy(namebuf, size, "Old Account");
		case TrustCProfilePoCBadge: strcopy(namebuf, size, "Community Badge");
		case TrustNoVACBans: strcopy(namebuf, size, "No VAC Ban");
		case TrustNotEconomyBanned: strcopy(namebuf, size, "No Trade Ban");
		case TrustSBPPGameBan: strcopy(namebuf, size, "No SB Ban");
		case TrustSBPPCommBan: strcopy(namebuf, size, "No SB CommBan");
	}
}
#endif

public void OnMapStart() {
	accountCustomTextures.Clear();
}

public void OnClientConnected(int client) {
	clientUGCloaded[client] = false;
	clientNotifiedGrants[client] = false;
	clientUGC[client] = ugcNone;
	clientSprayFile[client][0]=0;
	clientJingleFile[client][0]=0;
}
public void OnClientPutInServer(int client) {
	char buffer[32];
	if (GetPlayerDecalFile(client, buffer, sizeof(buffer))) {
		Format(clientSprayFile[client], sizeof(clientSprayFile[]), "user_custom/%c%c/%s.dat", buffer[0], buffer[1], buffer);
	}
	if (GetPlayerJingleFile(client, buffer, sizeof(buffer))) {
		Format(clientJingleFile[client], sizeof(clientJingleFile[]), "user_custom/%c%c/%s.dat", buffer[0], buffer[1], buffer);
	}
}
public void OnClientDisconnect(int client) {
	OnClientConnected(client); //cleanup is the same
}

#if defined _trustfactor_included
public void OnClientTrustFactorLoaded(int client, TrustFactors factors) {
	clientUGCloaded[client] = true;
	UpdateAllowedUGC(client);
}
public void OnClientTrustFactorChanged(int client, TrustFactors oldFactors, TrustFactors newFactors) {
	UpdateAllowedUGC(client);
}
#endif

public void OnClientPostAdminCheck(int client) {
	//this is logged a bit later so we don't spam the log with connection requests from banned clients
	if (bLogUserCustomUploads && !IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client)) {
		LogToFileEx(UGC_LOGFILE, "Linked User File %s to %L", clientSprayFile[client], client);
		LogToFileEx(UGC_LOGFILE, "Linked User File %s to %L", clientJingleFile[client], client);
	}
}


static void UpdateAllowedUGCAll() {
	for (int client=1; client<=MaxClients; client++) {
#if defined _trustfactor_included
		if (IsClientTrustFactorLoaded(client))
			UpdateAllowedUGC(client);
#else
		if (IsValidClient(client))
			UpdateAllowedUGC(client);
#endif
	}
}
static void UpdateAllowedUGC(int client) {
	if (!IsClientInGame(client) || IsFakeClient(client)) return;
	eUserGeneratedContent flags = ugcNone, previously = clientUGC[client];
#if defined _trustfactor_included
	if (trust_Spray.Test(client)) flags |= ugcSpray;
	if (trust_Jingle.Test(client)) flags |= ugcJingle;
	if (GetEngineVersion() == Engine_TF2) {
		if (trust_Decal.Test(client)) flags |= ugcDecal;
		if (trust_Name.Test(client)) flags |= ugcName;
		if (trust_Description.Test(client)) flags |= ugcDescription;
	}
#else
	flags = ugcSpray|ugcJingle;
	if (GetEngineVersion() == Engine_TF2) {
		flags |= ugcDecal|ugcName|ugcDescription;
	}
#endif
	flags &=~ blockUGCTypes;
	clientUGC[client]=flags;

	//this update below only if call is late
	if (IsClientInGame(client) && GetClientTeam(client) > 1) {
		CheckClientItems(client);
		if (!(flags & ugcSpray))
			KillSpray(client);
	}

	if (flags != previously) {
		clientNotifiedGrants[client]=false;
		NotifyClientGrants(client);
	}
}

static void NotifyClientGrants(int client) {
	if (clientNotifiedGrants[client]) return; //already notified
	if (!IsClientInGame(client)) return; //not yet available to be notified
	clientNotifiedGrants[client]=true;

	char buffer[72];
	UGCFlagString(clientUGC[client], buffer, sizeof(buffer));
	PrintToChat(client, "[SM] You are allowed to use %s", buffer);
}

public void OnEvent_ClientInventoryRegeneratePost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid", 0));
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client) || IsClientReplay(client) || IsClientSourceTV(client) || TF2_GetClientTeam(client)<=TFTeam_Spectator) return;
	if (clientUGCloaded[client])
		UpdateAllowedUGC(client);
	NotifyClientGrants(client);
	CheckClientItems(client);
}
public void OnEntityCreated(int entity, const char[] classname){
	if (GetEngineVersion() != Engine_TF2 && StrEqual(classname, "player"))
		SDKHook(entity, SDKHook_SpawnPost, OnClientSpawnPost);
}
public void OnClientSpawnPost(int client) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client) || IsClientReplay(client) || IsClientSourceTV(client) || GetClientTeam(client)<=1) return;
	if (clientUGCloaded[client])
		UpdateAllowedUGC(client);
	NotifyClientGrants(client);
}

void CheckClientItems(int client) {
	if (GetEngineVersion() != Engine_TF2) return;
	eUserGeneratedContent flags;
	char buffer[256];
	char slotName[24];

	for (int slot;slot<4;slot++) {
		int weapon = TF2Util_GetPlayerLoadoutEntity(client, slot);
		if (weapon != INVALID_ENT_REFERENCE) {
			flags = UGCCheckItem(weapon,client) & ~clientUGC[client];
			if (flags == ugcDecal) {
				RemoveItemDecal(weapon);
				TF2Econ_TranslateLoadoutSlotIndexToName(slot, slotName, sizeof(slotName));
				PrintToChat(client, "[SM] The decal was removed from your %s", slotName);
			} else if (flags) {
				TF2_RemoveWeaponSlot(client, slot);
				TF2Econ_TranslateLoadoutSlotIndexToName(slot, slotName, sizeof(slotName));
				UGCFlagString(flags & ~clientUGC[client], buffer, sizeof(buffer));
				PrintToChat(client, "[SM] Your %s was blocked for it's %s", slotName, buffer);
			}
		}
	}
	int to = TF2Util_GetPlayerWearableCount(client);
	int entity;
	ArrayStack blocked = new ArrayStack();
	eUserGeneratedContent flags2;
	for (int wno; wno < to; wno++) {
		flags = UGCCheckItem(entity = TF2Util_GetPlayerWearable(client, wno), client) & ~clientUGC[client];
		if (flags) {
			blocked.Push(entity);
			flags2 |= flags;
		}
	}
	if (!blocked.Empty) {
		UGCFlagString(flags2, buffer, sizeof(buffer));
		PrintToChat(client, "[SM] One or more cosmetics were blocked for their %s", buffer);
		while (!blocked.Empty) TF2_RemoveWearable(client, blocked.Pop());
	}
	delete blocked;
}
static eUserGeneratedContent UGCCheckItem(int entity, int owner) {
	eUserGeneratedContent ugc = ugcNone;
	int item = GetItemDefinitionIndex(entity);
	if (item < 0) return ugc;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	int ugch, ugcl;

	int aidx[32];
	any aval[32];
	int acnt = TF2Attrib_GetSOCAttribs(entity, aidx, aval);
	for (int i;i<acnt;i++) switch(aidx[i]) {
		case 152: if ((ugcl=aval[i])!=0) ugc |= ugcDecal;
		case 227: if ((ugch=aval[i])!=0) ugc |= ugcDecal;
		case 500: if (aval[i]!=0) ugc |= ugcName;
		case 501: if (aval[i]!=0) ugc |= ugcDescription;
	}

	if (ugch || ugcl) {
		char buffer[64];
		GetClientAuthId(owner, AuthId_SteamID64, buffer, sizeof(buffer));
		Format(buffer,sizeof(buffer),"%s_%08X%08X", buffer, ugch,ugcl);
		int val;
		if (!accountCustomTextures.GetValue(buffer,val)) {
			accountCustomTextures.SetValue(buffer,1);
			LogToFileEx(UGC_LOGFILE, "Custom Texture %08X%08X on ItemDef %i (%s) from %L",
				ugch,ugcl, GetItemDefinitionIndex(entity), classname, owner);
		}
	}

// requires nosoops experimental branch of tf2attributes, but would be able to check slurs
//	char itemName[128];
//	char itemDesc[256];
//	TF2Attrib_HookValueString("", "custom_name_attr", entity, itemName, sizeof(itemName));
//	if (itemName[0]) ugc |= ugcName;
//	TF2Attrib_HookValueString("", "custom_desc_attr", entity, itemDesc, sizeof(itemDesc));
//	if (itemDesc[0]) ugc |= ugcDescription;

	return ugc & checkUGCTypes;
}

static void RemoveItemDecal(int weapon) {
	//we need to overwrite the value, as it's a SOC value. 'Removing' has no effect
	TF2Attrib_SetByDefIndex(weapon, 152, 0.0);
	TF2Attrib_SetByDefIndex(weapon, 227, 0.0);
	TF2Attrib_ClearCache(weapon);
}

public Action OnTempEnt_PlayerDecal(const char[] name, const int[] clients, int count, float delay) {
	int client = TE_ReadNum("m_nPlayer");
	int target = TE_ReadNum("m_nEntity");
	float origin[3];
	TE_ReadVector("m_vecOrigin", origin);
	if (origin[0]==123456.0 && origin[1]==123456.0 && origin[2]==123456.0 && target==0) return Plugin_Continue; //"deleting" spray

	if (!IsValidClient(client)) return Plugin_Handled;
	if (!(checkUGCTypes&ugcSpray) || clientUGC[client]&ugcSpray) return Plugin_Continue;

	PrintToChat(client, "[SM] Your spray was blocked");
	return Plugin_Handled;
}
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (impulse == 202 && (checkUGCTypes&ugcJingle) && !(clientUGC[client]&ugcJingle)) {
		impulse = 0;
		PrintToChat(client, "[SM] Your jingle was blocked");
		return Plugin_Changed;
	}
	return Plugin_Continue;
}


static bool IsValidClient(int client) {
	return 1<=client<=MaxClients && IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client);
}

static int GetItemDefinitionIndex(int entity) {
	if (entity > 0 && HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex"))
		return GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
	else
		return -1;
}

static void KillSpray(int client) {
	if (!IsValidClient(client))
		return;

	float vec[3]={123456.0,123456.0,123456.0};
	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", vec);
	TE_WriteNum("m_nEntity", 0);
	TE_WriteNum("m_nPlayer", client);
	TE_SendToAll();
}

static void UGCFlagString(eUserGeneratedContent flags, char[] string, int maxlen) {
	string[0]=0;
	if (flags == ugcNone) {
		strcopy(string, maxlen, "<Nothing>");
		return;
	}
	if (flags&ugcDecal)
		StrCat(string, maxlen, "Custom Decals");
	if (flags&ugcName) {
		if (string[0]!=0) StrCat(string, maxlen, ", ");
		StrCat(string, maxlen, "Custom Names");
	}
	if (flags&ugcDescription) {
		if (string[0]!=0) StrCat(string, maxlen, ", ");
		StrCat(string, maxlen, "Custom Descriptions");
	}
	if (flags&ugcSpray) {
		if (string[0]!=0) StrCat(string, maxlen, ", ");
		StrCat(string, maxlen, "Sprays");
	}
	if (flags&ugcJingle) {
		if (string[0]!=0) StrCat(string, maxlen, ", ");
		StrCat(string, maxlen, "Jingles");
	}
}

//void PrintToAdmins(AdminFlag flag, const char[] format, any...) {
//	char msg[1024];
//	VFormat(msg, sizeof(msg), format, 2);
//	PrintToServer("%s", msg);
//	for (int client=1;client<=MaxClients;client++) {
//		if (!IsValidClient(client) || !IsClientAuthorized(client) || !GetAdminFlag(GetUserAdmin(client), flag)) continue;
//		PrintToChat(client, "%s", msg);
//	}
//}

//might want to check stuff again at some point
//void DumpAllAttributes(int entity) {
//	int indices[20];
//	int max = TF2Attrib_ListDefIndices(entity, indices);
//	any value;
//	Address address;
//	for (int i; i<max; i++) {
//		address = TF2Attrib_GetByDefIndex(entity, indices[i]);
//		value = TF2Attrib_GetValue(address);
//		PrintToServer("  ent %i : %i / %f", indices[i], value, value);
//	}
//
//	ArrayList statics = TF2Econ_GetItemStaticAttributes(GetItemDefinitionIndex(entity));
//	for (int i; i<statics.Length; i++) {
//		PrintToServer("  sta %i : %i / %f", statics.Get(i,0), statics.Get(i,1), statics.Get(i,1));
//	}
//	delete statics;
//
//	int attribs[16];
//	float values[16];
//	max = TF2Attrib_GetSOCAttribs(entity, attribs, values);
//	for (int i; i<max; i++) {
//		PrintToServer("  SOC %i : %i / %f", attribs[i], values[i], values[i]);
//	}
//}
