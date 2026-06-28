#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

public Plugin myinfo =
{
    name = "No Spray Cooldown",
    author = "mogvincible",
    description = "Removes spray cooldown by forcing decalfrequency to 0.",
    version = "1.0"
};

public void OnPluginStart()
{
    ForceSprayCooldown();
}

public void OnMapStart()
{
    ForceSprayCooldown();
}

void ForceSprayCooldown()
{
    ConVar cvar = FindConVar("decalfrequency");
    if (cvar != null)
    {
        cvar.SetFloat(0.0, true, true);
    }
}