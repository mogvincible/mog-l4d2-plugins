#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define UPGRADE_INCENDIARY 1
#define UPGRADE_EXPLOSIVE  2
#define UPGRADE_LASER      4

public Plugin myinfo =
{
    name = "Incendiary Ammo Pickup To Ammo Laser",
    author = "mogvincible",
    description = "Picking up incendiary ammo gives max ammo + laser sights, but no fire bullets.",
    version = "1.2"
};

public void OnPluginStart()
{
    // This fires when a survivor actually presses E and takes ammo from the deployed pack.
    HookEvent("upgrade_pack_added", Event_UpgradePackAdded, EventHookMode_Post);
}

public void Event_UpgradePackAdded(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidSurvivor(client))
        return;

    // Delay very slightly so the game gives fire bullets first, then we remove them.
    CreateTimer(0.1, Timer_ReplaceUpgrade, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ReplaceUpgrade(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidSurvivor(client))
        return Plugin_Stop;

    // Give max reserve ammo.
    CheatCommand(client, "give", "ammo");

    // Give laser sight through game command.
    CheatCommand(client, "upgrade_add", "LASER_SIGHT");

    int weapon = GetPlayerWeaponSlot(client, 0);

    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");

        // Remove incendiary/explosive ammo, keep/add laser.
        bits &= ~UPGRADE_INCENDIARY;
        bits &= ~UPGRADE_EXPLOSIVE;
        bits |= UPGRADE_LASER;

        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

        // Remove the actual loaded fire/explosive rounds.
        if (HasEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded"))
        {
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 0);
        }
    }

    return Plugin_Stop;
}

bool IsValidSurvivor(int client)
{
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && IsPlayerAlive(client)
        && GetClientTeam(client) == 2;
}

void CheatCommand(int client, const char[] command, const char[] args)
{
    int flags = GetCommandFlags(command);
    SetCommandFlags(command, flags & ~FCVAR_CHEAT);

    FakeClientCommand(client, "%s %s", command, args);

    SetCommandFlags(command, flags);
}