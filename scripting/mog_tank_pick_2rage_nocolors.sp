#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// We declare these ourselves so you do NOT need left4dhooks.inc to compile.
native void L4D2Direct_SetTankTickets(int client, int tickets);
native int L4D2Direct_GetTankPassedCount();
native void L4D2Direct_SetTankPassedCount(int count);

#define TEAM_INFECTED 3
#define ZOMBIECLASS_TANK 8

ConVar g_hAnnounceAll;
ConVar g_hRageRefills;
ConVar g_hDebug;

bool g_bLeftSafe;
bool g_bAnnounced;

int g_iQueuedTankUserId;
int g_iRageRefillsUsed;

char g_sQueuedTankSteam[64];
char g_sQueuedTankName[MAX_NAME_LENGTH];

public Plugin myinfo =
{
	name = "[L4D2] Tank Pick + 2 Rage",
	author = "mogvincible",
	description = "Announces selected Tank after saferoom leave and gives that Tank two rage bars total.",
	version = "1.1",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("L4D2Direct_SetTankTickets");
	MarkNativeAsOptional("L4D2Direct_GetTankPassedCount");
	MarkNativeAsOptional("L4D2Direct_SetTankPassedCount");
	return APLRes_Success;
}

public void OnPluginStart()
{
	if (GetFeatureStatus(FeatureType_Native, "L4D2Direct_SetTankTickets") != FeatureStatus_Available)
	{
		SetFailState("Left4DHooks Direct is required. Missing L4D2Direct_SetTankTickets.");
	}

	g_hAnnounceAll = CreateConVar(
		"mog_tank_announce_all",
		"1",
		"Who sees the Tank selection? 0 = infected/spectators only, 1 = everyone.",
		FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);

	g_hRageRefills = CreateConVar(
		"mog_tank_rage_refills",
		"1",
		"How many times to refill the original Tank rage before allowing AI. 1 = two rage bars total.",
		FCVAR_NOTIFY,
		true, 0.0,
		true, 5.0
	);

	g_hDebug = CreateConVar(
		"mog_tank_debug",
		"0",
		"Print debug info to server console.",
		FCVAR_NOTIFY,
		true, 0.0,
		true, 1.0
	);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

	HookEventEx("player_left_start_area", Event_LeftSafeArea, EventHookMode_PostNoCopy);
	HookEventEx("player_left_safe_area", Event_LeftSafeArea, EventHookMode_PostNoCopy);

	RegConsoleCmd("sm_tank", Command_Tank);
	RegConsoleCmd("sm_boss", Command_Tank);

	AutoExecConfig(true, "mog_tank_pick_2rage");
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	ResetRoundData();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	ResetRoundData();
}

void ResetRoundData()
{
	g_bLeftSafe = false;
	g_bAnnounced = false;

	g_iQueuedTankUserId = 0;
	g_iRageRefillsUsed = 0;

	g_sQueuedTankSteam[0] = '\0';
	g_sQueuedTankName[0] = '\0';
}

public void Event_LeftSafeArea(Event event, const char[] name, bool dontBroadcast)
{
	if (g_bLeftSafe)
		return;

	g_bLeftSafe = true;

	if (ChooseQueuedTank())
	{
		ApplyTankTickets();
		AnnounceQueuedTank();
	}
	else
	{
		PrintTankMessage(0, "\x04[Tank] No human infected player available for Tank selection.");
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bLeftSafe || g_sQueuedTankSteam[0] == '\0')
		return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
		return;

	char steam[64];
	if (!GetClientAuthId(client, AuthId_Steam2, steam, sizeof(steam)))
		return;

	if (!StrEqual(steam, g_sQueuedTankSteam))
		return;

	CreateTimer(0.2, Timer_RechooseTank);
}

public Action Timer_RechooseTank(Handle timer)
{
	if (!g_bLeftSafe)
		return Plugin_Stop;

	if (IsValidQueuedTank())
		return Plugin_Stop;

	if (ChooseQueuedTank())
	{
		ApplyTankTickets();
		AnnounceQueuedTank();
	}

	return Plugin_Stop;
}

public Action Command_Tank(int client, int args)
{
	if (client <= 0 || !IsClientInGame(client))
		return Plugin_Handled;

	if (!CanClientSeeTankMessage(client))
		return Plugin_Handled;

	if (g_sQueuedTankName[0] == '\0')
	{
		SendTankChat(client, 0, "\x04[Tank] Tank has not been selected yet.");
		return Plugin_Handled;
	}

	int queued = GetClientOfUserId(g_iQueuedTankUserId);

	if (queued == client)
	{
		SendTankChat(client, 0, "\x04[Tank] You are getting Tank this round.");
	}
	else if (queued > 0 && IsClientInGame(queued))
	{
		SendTankChat(client, queued, "\x04[Tank] \x03%N \x04is getting Tank this round.", queued);
	}
	else
	{
		SendTankChat(client, 0, "\x04[Tank] %s was selected for Tank, but may have left/swapped.", g_sQueuedTankName);
	}

	return Plugin_Handled;
}

// Left4DHooks forward.
// Called when the game is about to offer/control Tank.
// If tank_index is a human Tank, this is usually frustration/rage hitting 0.
public Action L4D_OnTryOfferingTankBot(int tank_index, bool &enterStatis)
{
	if (tank_index <= 0 || tank_index > MaxClients || !IsClientInGame(tank_index))
		return Plugin_Continue;

	// Human Tank rage hit 0. Refill once so the same player gets 2 rage bars total.
	if (!IsFakeClient(tank_index) && IsTank(tank_index))
	{
		int maxRefills = g_hRageRefills.IntValue;

		if (g_iRageRefillsUsed < maxRefills)
		{
			g_iRageRefillsUsed++;

			SetTankFrustration(tank_index, 100);

			int passedCount = L4D2Direct_GetTankPassedCount();
			L4D2Direct_SetTankPassedCount(passedCount + 1);

			// Both teams see this message.
			PrintTankMessageAllFrom(tank_index, "\x04[Tank] \x03%N \x04rage refilled. [%d/%d]", tank_index, g_iRageRefillsUsed, maxRefills);

			if (g_hDebug.BoolValue)
			{
				PrintToServer("[mog_tank] Refilled rage for %N. PassedCount %d -> %d",
					tank_index,
					passedCount,
					passedCount + 1
				);
			}

			return Plugin_Handled;
		}

		// Only the Tank player sees this message.
		PrintTankMessage(tank_index, "\x04[Tank] You used all rage refills. Next loss goes AI.");
		return Plugin_Continue;
	}

	// AI Tank is being offered to a player. Make sure our chosen player gets the tickets.
	if (IsFakeClient(tank_index))
	{
		if (!IsValidQueuedTank())
		{
			ChooseQueuedTank();
		}

		ApplyTankTickets();

		if (!g_bAnnounced && g_sQueuedTankName[0] != '\0')
		{
			AnnounceQueuedTank();
		}
	}

	return Plugin_Continue;
}

// Left4DHooks forward.
// Tracks when a player actually receives Tank.
// Public "has control of the Tank" chat message was removed.
public void L4D2_OnTankPassControl(int oldTank, int newTank, int passCount)
{
	if (newTank <= 0 || newTank > MaxClients || !IsClientInGame(newTank) || IsFakeClient(newTank))
		return;

	g_iQueuedTankUserId = GetClientUserId(newTank);
	GetClientName(newTank, g_sQueuedTankName, sizeof(g_sQueuedTankName));
	GetClientAuthId(newTank, AuthId_Steam2, g_sQueuedTankSteam, sizeof(g_sQueuedTankSteam));

	g_iRageRefillsUsed = 0;
}

bool ChooseQueuedTank()
{
	int clients[MAXPLAYERS + 1];
	int count = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanInfected(i))
			continue;

		clients[count++] = i;
	}

	if (count <= 0)
		return false;

	int chosen = clients[GetRandomInt(0, count - 1)];

	g_iQueuedTankUserId = GetClientUserId(chosen);
	GetClientName(chosen, g_sQueuedTankName, sizeof(g_sQueuedTankName));
	GetClientAuthId(chosen, AuthId_Steam2, g_sQueuedTankSteam, sizeof(g_sQueuedTankSteam));

	if (g_hDebug.BoolValue)
	{
		PrintToServer("[mog_tank] Queued Tank: %N / %s", chosen, g_sQueuedTankSteam);
	}

	return true;
}

void ApplyTankTickets()
{
	int chosen = GetClientOfUserId(g_iQueuedTankUserId);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanInfected(i))
			continue;

		L4D2Direct_SetTankTickets(i, i == chosen ? 20000 : 0);
	}
}

void AnnounceQueuedTank()
{
	g_bAnnounced = true;

	int chosen = GetClientOfUserId(g_iQueuedTankUserId);

	if (chosen > 0 && IsClientInGame(chosen))
	{
		PrintTankMessageFrom(chosen, 0, "\x04[Tank] \x03%N \x04is getting Tank this round.", chosen);
	}
	else if (g_sQueuedTankName[0] != '\0')
	{
		PrintTankMessage(0, "\x04[Tank] %s is getting Tank this round.", g_sQueuedTankName);
	}
}




void PrintTankMessageAllFrom(int colorSource, const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 3);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		SendTankChatRaw(i, colorSource, buffer);
	}
}

void PrintTankMessage(int target, const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 3);
	PrintTankMessageBuffer(0, target, buffer);
}

void PrintTankMessageFrom(int colorSource, int target, const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 4);
	PrintTankMessageBuffer(colorSource, target, buffer);
}

void PrintTankMessageBuffer(int colorSource, int target, const char[] buffer)
{
	if (target > 0)
	{
		if (IsClientInGame(target) && CanClientSeeTankMessage(target))
			SendTankChatRaw(target, colorSource, buffer);

		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		if (!CanClientSeeTankMessage(i))
			continue;

		SendTankChatRaw(i, colorSource, buffer);
	}
}

void SendTankChat(int client, int colorSource, const char[] format, any ...)
{
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 4);
	SendTankChatRaw(client, colorSource, buffer);
}

void SendTankChatRaw(int client, int colorSource, const char[] message)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;

	if (colorSource <= 0 || colorSource > MaxClients || !IsClientInGame(colorSource))
	{
		colorSource = client;
	}

	Handle hMsg = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	if (hMsg == null)
		return;

	BfWriteByte(hMsg, colorSource);
	BfWriteByte(hMsg, true);
	BfWriteString(hMsg, message);
	EndMessage();
}

bool CanClientSeeTankMessage(int client)
{
	if (g_hAnnounceAll.BoolValue)
		return true;

	int team = GetClientTeam(client);
	return team == TEAM_INFECTED || team == 1; // infected or spectator
}

bool IsValidQueuedTank()
{
	int client = GetClientOfUserId(g_iQueuedTankUserId);
	return IsHumanInfected(client);
}

bool IsHumanInfected(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& GetClientTeam(client) == TEAM_INFECTED;
}

bool IsTank(int client)
{
	if (client <= 0 || client > MaxClients)
		return false;

	if (!IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_INFECTED)
		return false;

	if (!IsPlayerAlive(client))
		return false;

	return GetEntProp(client, Prop_Send, "m_zombieClass") == ZOMBIECLASS_TANK;
}

void SetTankFrustration(int tank, int frustration)
{
	if (frustration < 0)
		frustration = 0;

	if (frustration > 100)
		frustration = 100;

	// L4D2 stores this reversed.
	// 0 = full rage, 100 = empty, so we set 100 - desired.
	SetEntProp(tank, Prop_Send, "m_frustration", 100 - frustration);
}