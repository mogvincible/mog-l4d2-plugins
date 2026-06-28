#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define MAX_ENTS 2048

bool g_bApplyingDamage[MAX_ENTS + 1];

public Plugin myinfo =
{
    name = "L4D2 Ignore Riot Armor",
    author = "mogvincible",
    description = "Makes riot commons take damage normally without changing their model.",
    version = "1.1",
    url = ""
};

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!StrEqual(classname, "infected"))
        return;

    if (entity <= 0 || entity > MAX_ENTS)
        return;

    SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype
)
{
    if (victim <= 0 || victim > MAX_ENTS)
        return Plugin_Continue;

    if (!IsValidEntity(victim))
        return Plugin_Continue;

    if (g_bApplyingDamage[victim])
        return Plugin_Continue;

    if (!IsRiotCommon(victim))
        return Plugin_Continue;

    if (damage <= 0.0)
        return Plugin_Continue;

    int health = GetEntProp(victim, Prop_Data, "m_iHealth");
    int dmg = RoundToCeil(damage);

    if (health <= dmg)
    {
        g_bApplyingDamage[victim] = true;
        SDKHooks_TakeDamage(victim, inflictor, attacker, 9999.0, damagetype);
        g_bApplyingDamage[victim] = false;

        return Plugin_Handled;
    }

    SetEntProp(victim, Prop_Data, "m_iHealth", health - dmg);

    return Plugin_Handled;
}

bool IsRiotCommon(int entity)
{
    if (!IsValidEntity(entity))
        return false;

    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    if (!StrEqual(classname, "infected"))
        return false;

    char model[PLATFORM_MAX_PATH];
    GetEntPropString(entity, Prop_Data, "m_ModelName", model, sizeof(model));

    if (StrContains(model, "riot", false) != -1)
        return true;

    return false;
}