#include <sourcemod>
#include <sdkhooks>
#include <regex>

#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <tf_econ_data>
#include <tf2utils>
#include <tf2attributes>
#define REQUIRE_PLUGIN

#include <trustfactor>

#define PLUGIN_VERSION "22w08a"

#pragma newdecls required
#pragma semicolon 1

enum eUserGeneratedContent (<<=1) {
	ugcNone=0,
	ugcSpray=1,
	ugcJingle, //this is an audatory version of sprays: wav @44.1kHz, max 512KiB
	ugcDecal,
	ugcName,
	ugcDescription,
}

static bool clientUGCloaded[MAXPLAYERS+1]; //did we load ugc flags?
static eUserGeneratedContent clientUGC[MAXPLAYERS+1]; //green-light flags for trusted 
static eUserGeneratedContent checkUGCTypes; //we only care to check those
static char clientSprayFile[MAXPLAYERS+1][128];
static char clientJingleFile[MAXPLAYERS+1][128];

static ConVar cvar_disable_Spray;
static ConVar cvar_disable_Jingle;
static ConVar cvar_disable_Decal;
static ConVar cvar_disable_Name;
static ConVar cvar_disable_Description;
static eUserGeneratedContent blockUGCTypes; //these are always blocked

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
static bool bConVarUpdates; //allow user flag updates from convar changes, disabled in plugin start

static ConVar cvar_logUploads;
static bool bLogUserCustomUploads;

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

public void OnPluginStart() {
	
	LoadTranslations("common.phrases");
	
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
	
	cvar_logUploads = CreateConVar("sm_ugc_log_uploads", "1", "Log all client file uploads to user_custom_received.log", FCVAR_HIDDEN|FCVAR_UNLOGGED, true, 0.0, true, 1.0);
	HookAndLoad(cvar_logUploads, OnCvarChange_LogUploads);
	
	AutoExecConfig();
	bConVarUpdates=true;
	
	AddTempEntHook("Player Decal", OnTempEnt_PlayerDecal);
	if (GetEngineVersion() == Engine_TF2) {
		HookEvent("post_inventory_application", OnEvent_ClientInventoryRegeneratePost, EventHookMode_Pre);
	} //for other games we use the spawn post sdkhook
	
	UpdateAllowedUGCAll();
	
	RegAdminCmd("sm_ugclookup", Command_LookupFile, ADMFLAG_KICK, "Usage: sm_ugclookup <userid|name|steamid|filename> - Lookup ugc filenames <-> SteamIDs. Return online players if any match, scan though log otherwise");
	RegAdminCmd("sm_ugclookuplogs", Command_LookupFile, ADMFLAG_KICK, "Usage: sm_ugclookuplogs <name|steamid|filename> - Lookup ugc filenames <-> SteamIDs. Scan log files directly");
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
		trust_Spray.Always();
	} else {
		checkUGCTypes |= ugcJingle;
		trust_Spray.Parse(val);
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
public void OnCvarChange_LogUploads(ConVar convar, const char[] oldValue, const char[] newValue) {
	bLogUserCustomUploads = convar.BoolValue;
}

// ===== Ok, boilerplate is over =====

public Action Command_LookupFile(int client, int args) {
	if (GetCmdArgs() < 1) {
		ReplyToCommand(client, "Requires a name, userid, steamid or (partial) filename");
		return Plugin_Handled;
	}
	char target[128];
	bool forcedLogs;
	GetCmdArg(0, target, sizeof(target));
	if (StrContains(target, "log", false)) forcedLogs=true;
	GetCmdArgString(target, sizeof(target));
	int online;
	{
		int results[1];
		char name[4];
		bool tnisml;
		int hits = ProcessTargetString(target, client, results, 1, COMMAND_FILTER_NO_MULTI|COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_BOTS, name, 0, tnisml);
		if (hits < 0) { //dont want a message on hits==0
			ReplyToTargetError(client, hits);
		} else if (hits > 0) {
			online = results[0];
		}
	}
	if (!forcedLogs && online > 0) {
		ReplyToCommand(client, "[UGC] Player '%L'", online);
		if (clientSprayFile[online][0]) ReplyToCommand(client, "[UGC] > Spray: %s", clientSprayFile[online]);
		else ReplyToCommand(client, "[UGC] > No Spray received");
		if (clientJingleFile[online][0]) ReplyToCommand(client, "[UGC] > Jingle: %s", clientJingleFile[online]);
		else ReplyToCommand(client, "[UGC] > No Jingle received");
		UGCFlagString(clientUGC[online], target, sizeof(target));
		ReplyToCommand(client, "[UGC] Has permission to %s", target);
	} else {
		File log = OpenFile("user_custom_received.log", "rt");
		if (log == INVALID_HANDLE) {
			ReplyToCommand(client, "[UGC] Logs not found");
		} else {
			Regex entry = new Regex("^L ([\\w\\/]+ - [0-9:]+): Received user_custom(.*) from (.*)<[0-9]+><(.*)><(?:Console)?>$", PCRE_UTF8|PCRE_CASELESS);
			char line[256];
			char matchTime[32], matchFile[32], matchName[64], matchSteamID[64];
			ArrayList hits = new ArrayList(ByteCountToCells(256));
			while (log.ReadLine(line, sizeof(line))) {
				if (entry.Match(line)>0) {
					entry.GetSubString(1, matchTime, sizeof(matchTime));
					entry.GetSubString(2, matchFile, sizeof(matchFile));
					entry.GetSubString(3, matchName, sizeof(matchName));
					entry.GetSubString(4, matchSteamID, sizeof(matchSteamID));
					
					if (StrContains(matchSteamID, target, false)>=0 || StrContains(matchName, target, false)>=0 || StrContains(matchFile, target, false)>=0) {
						Format(line, sizeof(line), " %s  %s<%s>  at %s", matchFile, matchName, matchSteamID, matchTime);
						hits.PushString(line);
					}
				}
			}
			delete log;
			delete entry;
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
		}
	}
	return Plugin_Handled;
}


public void OnMapStart() {
	if (bLogUserCustomUploads) {
		char mapName[128];
		GetCurrentMap(mapName, sizeof(mapName));
		LogToFileEx("user_custom_received.log", "----- Map Changed To %s -----", mapName);
	}
}
public Action OnFileReceive(int client, const char[] file) {
	if (bLogUserCustomUploads) {
		LogToFileEx("user_custom_received.log", "Received %s from %L", file, client);
	}
	return Plugin_Continue;
}
public Action OnFileSend(int client, const char[] file) {
	eUserGeneratedContent type;
	int owner = GetOwnerOfUserFile(file, type);
	if (owner < 0) {
//		PrintToServer("Blocking sending UGC: '%s' to %N, unknown owner", file, client);
		return Plugin_Handled;
	} else if (owner > 0 && (checkUGCTypes&type) && !(clientUGC[owner]&type)) {
//		PrintToServer("Blocking sending UGC: '%s' to %N, type not allowed from %L", file, client, owner);
		return Plugin_Handled;
	}
//	PrintToServer("Sending %s to %N", file, client);
	return Plugin_Continue;
}

public void OnClientConnected(int client) {
	clientUGCloaded[client] = false;
	clientUGC[client] = ugcNone;
	clientSprayFile[client][0]=0;
	clientJingleFile[client][0]=0;
}
public void OnClientPutInServer(int client) {
	char buffer[32];
	if (GetPlayerDecalFile(client, buffer, sizeof(buffer))) {
		Format(clientSprayFile[client], sizeof(clientSprayFile[]), "user_custom/%c%c/%s.dat", buffer[0], buffer[1], buffer);
//		PrintToServer("Assigned decal file %s to %N", clientSprayFile[client], client);
	}// else PrintToServer("Client %L has no decal file", client);
	if (GetPlayerJingleFile(client, buffer, sizeof(buffer))) {
		Format(clientJingleFile[client], sizeof(clientJingleFile[]), "user_custom/%c%c/%s.dat", buffer[0], buffer[1], buffer);
//		PrintToServer("Assigned jingle file %s to %N", clientJingleFile[client], client);
	}// else PrintToServer("Client %L has no jingle file", client);	
}
public void OnClientDisconnect_Post(int client) {
	OnClientConnected(client); //cleanup is the same
}


public void OnClientTrustFactorLoaded(int client, TrustFactors factors) {
	if (IsClientInGame(client) && TF2_GetClientTeam(client) > TFTeam_Spectator && !clientUGCloaded[client]) {
		clientUGCloaded[client] = true;
		UpdateAllowedUGC(client);
	}
}

public void OnClientTrustFactorChanged(int client, TrustFactors oldFactors, TrustFactors newFactors) {
	UpdateAllowedUGC(client);
}

static void UpdateAllowedUGCAll() {
	for (int client=1; client<=MaxClients; client++) {
		if (IsClientTrustFactorLoaded(client))
			UpdateAllowedUGC(client);
	}
}
static void UpdateAllowedUGC(int client) {
	eUserGeneratedContent flags = ugcNone, previously = clientUGC[client];
	if (trust_Spray.Test(client)) flags |= ugcSpray;
	if (trust_Jingle.Test(client)) flags |= ugcJingle;
	if (GetEngineVersion() == Engine_TF2) {
		if (trust_Decal.Test(client)) flags |= ugcDecal;
		if (trust_Name.Test(client)) flags |= ugcName;
		if (trust_Description.Test(client)) flags |= ugcDescription;
	}
	flags &=~ blockUGCTypes;
	clientUGC[client]=flags;
	
	CheckClientItems(client);
	if (!(flags & ugcSpray))
		KillSpray(client);
	
	if (flags != previously) {
		char buffer[72];
		UGCFlagString(flags, buffer, sizeof(buffer));
		PrintToChat(client, "[SM] You are allowed to use %s", buffer);
	}
}

public void OnEvent_ClientInventoryRegeneratePost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid", 0));
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || TF2_GetClientTeam(client)<=TFTeam_Spectator || IsFakeClient(client)) return;
	if (!clientUGCloaded[client]) {
		clientUGCloaded[client]=true;
		UpdateAllowedUGC(client);
	}
	CheckClientItems(client);
}
public void OnEntityCreated(int entity, const char[] classname){
	if (GetEngineVersion() != Engine_TF2 && StrEqual(classname, "player"))
		SDKHook(entity, SDKHook_SpawnPost, OnClientSpawnPost);
}
public void OnClientSpawnPost(int client) {
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client)<=1 || IsFakeClient(client)) return;
	if (!clientUGCloaded[client]) {
		clientUGCloaded[client]=true;
		UpdateAllowedUGC(client);
	}
}

void CheckClientItems(int client) {
	if (GetEngineVersion() != Engine_TF2) return;
	eUserGeneratedContent flags;
	char buffer[256];
	char slotName[24];
	
	for (int slot;slot<4;slot++) {
		int weapon = TF2Util_GetPlayerLoadoutEntity(client, slot);
		if (weapon != INVALID_ENT_REFERENCE) {
			flags = UGCCheckItem(weapon) & ~clientUGC[client];
			if (flags == ugcDecal) {
				RemoveItemDecal(weapon);
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
		flags = UGCCheckItem(entity = TF2Util_GetPlayerWearable(client, wno)) & ~clientUGC[client];
		if (flags) {
			blocked.Push(entity);
			flags2 |= flags;
		}
	}
	if (!blocked.Empty) {
		UGCFlagString(flags2, buffer, sizeof(buffer));
		PrintToChat(client, "[SM] One or more cosmetics were blocked for their %s", slotName, buffer);
		while (!blocked.Empty) TF2_RemoveWearable(client, blocked.Pop());
	}
}
static eUserGeneratedContent UGCCheckItem(int entity) {
	eUserGeneratedContent ugc = ugcNone;
	int item = GetItemDefinitionIndex(entity);
	if (item < 0) return ugc;
	
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	
	int aidx[16];
	any aval[16];
	int acnt = TF2Attrib_GetSOCAttribs(entity, aidx, aval);
	for (int i;i<acnt;i++) switch(aidx[i]) {
		case 152: if (aval[i]) ugc |= ugcDecal;
		case 227: if (aval[i]) ugc |= ugcDecal;
		case 500: if (aval[i]) ugc |= ugcName;
		case 501: if (aval[i]) ugc |= ugcDescription;
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
	if (origin[0]==0 && origin[1]==0 && origin[2]==0 && target==0) return Plugin_Continue; //"deleting" spray
	
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



static int GetOwnerOfUserFile(const char[] file, eUserGeneratedContent& type) {
	if (StrContains(file,"user_custom/")==0) {
		for (int client=1;client<=MaxClients;client++) {
			if (!IsClientConnected(client)) continue;
			if (StrEqual(clientSprayFile[client], file)) {
				type = ugcSpray;
				return client;
			} else if (StrEqual(clientJingleFile[client], file)) {
				type = ugcJingle;
				return client;
			}
		}
		return -1; //unknown owner; this magically also hits for the default "no-jingle" file. idk why but ok i guess
	}
	return 0; //server owned
}

static bool IsValidClient(int client) {
	return 1<=client<=MaxClients && IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client);
}

static int GetItemDefinitionIndex(int entity) {
	if (HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex"))
		return GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");
	else
		return -1;
}

static void KillSpray(int client) {
	if (!IsValidClient(client))
		return;
	
	float vec[3];
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