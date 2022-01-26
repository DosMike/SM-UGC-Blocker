#include <sourcemod>
#include <tf2_stocks>

#include <tf_econ_data>
#include <tf2utils>
#include <tf2attributes>

#include <trustfactor>

#define PLUGIN_VERSION "22w03a"

#pragma newdecls required
#pragma semicolon 1

enum eUserGeneratedContent (<<=1) {
	ugcNone=0,
	ugcSpray=1,
	ugcDecal,
	ugcName,
	ugcDescription
}

static bool clientUGCloaded[MAXPLAYERS+1]; //did we load ugc flags?
static eUserGeneratedContent clientUGC[MAXPLAYERS+1]; //green-light flags for trusted 
static eUserGeneratedContent checkUGCTypes; //we only care to check those
static ConVar cvar_disable_Spray;
static ConVar cvar_disable_Decal;
static ConVar cvar_disable_Name;
static ConVar cvar_disable_Description;
static eUserGeneratedContent blockUGCTypes; //these are always blocked

static ConVar cvar_trust_Spray;
static ConVar cvar_trust_Decal;
static ConVar cvar_trust_Name;
static ConVar cvar_trust_Description;
static TrustFactors trustFlags_Spray;
static TrustFactors trustFlags_Decal;
static TrustFactors trustFlags_Name;
static TrustFactors trustFlags_Description;
static int trustLevel_Spray;
static int trustLevel_Decal;
static int trustLevel_Name;
static int trustLevel_Description;

static bool bConVarUpdates;

public Plugin myinfo = {
	name = "[TF2] UGC Blocker",
	author = "reBane",
	description = "Block User Generated Content (Sprays Decal Names Descritions)",
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
	cvar_disable_Spray = CreateConVar("sm_ugc_disable_spray", "0", "Always block players from using sprays", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	cvar_disable_Decal = CreateConVar("sm_ugc_disable_decal", "0", "Always block items with custom decals", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	cvar_disable_Name = CreateConVar("sm_ugc_disable_name", "0", "Always block items with custom names", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	cvar_disable_Description = CreateConVar("sm_ugc_disable_description", "0", "Always block items with custom descriptions", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	cvar_trust_Spray = CreateConVar("sm_ugc_trust_spray", "tfdpslgob3", "TrustFlags required to allow sprays, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD);
	cvar_trust_Decal = CreateConVar("sm_ugc_trust_decal", "tfdpslgob3", "TrustFlags required to allow items with custom decals, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD);
	cvar_trust_Name = CreateConVar("sm_ugc_trust_name", "tfdpslgob3", "TrustFlags required to allow items with custom names, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD);
	cvar_trust_Description = CreateConVar("sm_ugc_trust_description", "tfdpslgob3", "TrustFlags required to allow items with custom descriptions, empty to always allow", FCVAR_HIDDEN|FCVAR_UNLOGGED|FCVAR_DONTRECORD);
	HookAndLoad(cvar_disable_Spray, OnCvarChange_DisableSpray);
	HookAndLoad(cvar_disable_Decal, OnCvarChange_DisableDecal);
	HookAndLoad(cvar_disable_Name, OnCvarChange_DisableName);
	HookAndLoad(cvar_disable_Description, OnCvarChange_DisableDescription);
	HookAndLoad(cvar_trust_Spray, OnCvarChange_TrustSpray);
	HookAndLoad(cvar_trust_Decal, OnCvarChange_TrustDecal);
	HookAndLoad(cvar_trust_Name, OnCvarChange_TrustName);
	HookAndLoad(cvar_trust_Description, OnCvarChange_TrustDescription);
	AutoExecConfig();
	bConVarUpdates=true;
	
	AddTempEntHook("Player Decal", OnTempEnt_PlayerDecal);
	HookEvent("post_inventory_application", OnEvent_ClientInventoryRegeneratePost, EventHookMode_Pre);
	
	UpdateAllowedUGCAll();
}

public void OnCvarChange_DisableSpray(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar.BoolValue) blockUGCTypes |= ugcSpray; else blockUGCTypes &=~ ugcSpray;
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
		trustLevel_Spray = 0;
	} else {
		checkUGCTypes |= ugcSpray;
		trustFlags_Spray = ReadTrustFactorString(val, _, trustLevel_Spray);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustDecal(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcDecal;
		trustLevel_Decal = 0;
	} else {
		checkUGCTypes |= ugcDecal;
		trustFlags_Decal = ReadTrustFactorString(val, _, trustLevel_Decal);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustName(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcName;
		trustLevel_Name = 0;
	} else {
		checkUGCTypes |= ugcName;
		trustFlags_Name = ReadTrustFactorString(val, _, trustLevel_Name);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}
public void OnCvarChange_TrustDescription(ConVar convar, const char[] oldValue, const char[] newValue) {
	char val[32];
	strcopy(val,sizeof(val),newValue);
	TrimString(val);
	if (val[0]==0) {
		checkUGCTypes &=~ ugcDescription;
		trustLevel_Description = 0;
	} else {
		checkUGCTypes |= ugcDescription;
		trustFlags_Description = ReadTrustFactorString(val, _, trustLevel_Description);
	}
	if (bConVarUpdates) UpdateAllowedUGCAll();
}


public void OnClientConnected(int client) {
	clientUGCloaded[client] = false;
	clientUGC[client]=ugcNone;
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
	if (CheckClientTrust(client, trustFlags_Spray, trustLevel_Spray)) flags |= ugcSpray;
	if (CheckClientTrust(client, trustFlags_Decal, trustLevel_Decal)) flags |= ugcDecal;
	if (CheckClientTrust(client, trustFlags_Name, trustLevel_Name)) flags |= ugcName;
	if (CheckClientTrust(client, trustFlags_Description, trustLevel_Description)) flags |= ugcDescription;
	flags &=~ blockUGCTypes;
	clientUGC[client]=flags;
	
	CheckClientItems(client);
	if (!(flags & ugcSpray))
		KillSpray(client);
	
	if (flags != previously) {
		char buffer[64];
		UGCFlagString(flags, buffer, sizeof(buffer));
		PrintToChat(client, "[SM] You are allowed to use %s", buffer);
	}
}

public void OnEvent_ClientInventoryRegeneratePost(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid", 0));
	if (!clientUGCloaded[client]) {
		clientUGCloaded[client]=true;
		UpdateAllowedUGC(client);
	}
	CheckClientItems(client);
}

void CheckClientItems(int client) {
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