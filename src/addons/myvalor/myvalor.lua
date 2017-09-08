
_addon.author   = 'Eleven Pies';
_addon.name     = 'MyValor';
_addon.version  = '2.0.0';

require 'common'
require 'mob.mobinfo'

local lor_packets = require 'lor.lor_packets_mod'

---------------------------------------------------------------------------------------------------
-- desc: MyValor global table.
---------------------------------------------------------------------------------------------------
local statusvalor = { };

local lastmobitem;

local basicMessageDefinitions = { };

basicMessageDefinitions[  6] = { hasSpell = false, resolveTarget = true, showDecayTime = false, useDuration = false }; -- The <player> defeats <target>.
basicMessageDefinitions[ 20] = { hasSpell = false, resolveTarget = true, showDecayTime = false, useDuration = false }; -- <target> falls to the ground.

local defaultBasicMessageDefinitions = { hasSpell = false, resolveTarget = false, showDecayTime = false, useDuration = false };

local lastrender = 0;

local creditMap = { };

-- Labyrinth of Onzozo
creditMap[213] = {
    ["Goblin Bouncer"] = "Goblin",
    ["Goblin Enchanter"] = "Goblin",
    ["Goblin Hunter"] = "Goblin",
    ["Goblin Miner"] = "Goblin",
    ["Goblin Poacher"] = "Goblin",
    ["Goblin Robber"] = "Goblin",
    ["Goblin Reaper"] = "Goblin",
    ["Goblin Trader"] = "Goblin"
};

local currentCreditMap;

---------------------------------------------------------------------------------------------------
-- desc: Default MyValor configuration table.
---------------------------------------------------------------------------------------------------
local default_config =
{
    font =
    {
        name        = 'Tahoma',
        size        = 10,
        color       = 0xFFFFFFFF,
        ----position    = { 50, 125 },
        position    = { 50, 200 },
        bgcolor     = 0x80000000,
        bgvisible   = true
    },
    colors =
    {
        default_color = '255,255,176'
    }
};
local myvalor_config = default_config;

local function unsz(s)
    local pos = string.find(s, '\0');
    if (pos ~= nil and pos > 0) then
        return string.sub(s, 1, pos - 1);
    end

    return s;
end

---------------------------------------------------------------------------------------------------
-- func: color_entry
-- desc: Colors an entry.
---------------------------------------------------------------------------------------------------
local function color_entry(s, c)
    return string.format('\\cs(%s)%s\\cr', c, s);
end

local function findEntity(entityid)
    -- targid < 0x400
    --   TYPE_MOB || TYPE_NPC || TYPE_SHIP
    -- targid < 0x700
    --   TYPE_PC
    -- targid < 0x800
    --   TYPE_PET

    -- Search players
    for x = 0x400, 0x6FF do
        local ent = GetEntity(x);
        if (ent ~= nil and ent.ServerID == entityid) then
            return { id = entityid, index = x, name = ent.Name };
        end
    end

    return nil;
end

local function getEntityInfo(zoneid, entityid)
    local zonemin = bit.lshift(zoneid, 12) + 0x1000000;

    local entityindex;
    local entityname;
    local entitytype;
    local isself = false;

    -- Check if entity looks like a mobid
    if (bit.band(zonemin, entityid) == zonemin) then
        entityindex = bit.band(entityid, 0xfff);
        entityname = MobNameFromTargetId(entityindex);
        entitytype = 0x04; -- TYPE_MOB
    else
        -- Otherwise try finding player in NPC map
        local entityResult = findEntity(entityid);
        if (entityResult ~= nil) then
            entityindex = entityResult.index;
            entityname = entityResult.name;
            entitytype = 0x01; -- TYPE_PC

            -- If player, determine if player is self
            local selftarget = AshitaCore:GetDataManager():GetParty():GetPartyMemberTargetIndex(0);
            if (entityindex == selftarget) then
                isself = true;
            end
        else
            entityindex = 0;
            entityname = nil;
            entitytype = 0x00;
        end
    end

    if (entityname == nil) then
        entityname = 'UNKNOWN_MOB';
    end

    -- Convert null terminated strings
    return { id = entityid, index = entityindex, name = unsz(entityname), entitytype = entitytype, isself = isself };
end

local function getMob(mobindex, mobname)
    if (mobindex > 2047) then -- Should never be greater than 0x7ff
        return nil;
    end

    -- Using mob name as a way to "roll up" mobs into the same group
    -- More complicated roll up could be needed in some cases
    local tmpMobName;

    -- If we have mapping for the current zone, try to use it
    if (currentCreditMap ~= nil) then
        tmpMobName = currentCreditMap[mobname];
    end

    -- If no suitable mapping was found, use the mob name directly
    if (tmpMobName == nil) then
        tmpMobName = mobname;
    end

    ----local mobkey = mobindex;
    local mobkey = tmpMobName;

    if (statusvalor.mobs == nil) then
        statusvalor.mobs = { };
    end

    local mobitem = statusvalor.mobs[mobkey];
    if (mobitem == nil) then
        mobitem = { };
        ----mobitem.index = mobindex;
        mobitem.name = tmpMobName;
        statusvalor.mobs[mobkey] = mobitem;
    end

    return mobitem;
end

local function handleMessageBasicPacket(id, size, packet)
    local zoneid = MobInfoZoneId();

    local pp = lor_packets.parse_action_message(packet);

    local actorInfo = getEntityInfo(zoneid, pp.actor_id); -- For debug purposes

    local hasTarget;
    local statusType;

    local messageDef = basicMessageDefinitions[pp.message_id];
    if (messageDef == nil) then
        messageDef = defaultBasicMessageDefinitions;
    end

    local targetInfo;

    if (messageDef.resolveTarget) then
        targetInfo = getEntityInfo(zoneid, pp.target_id);
        if (targetInfo ~= nil and targetInfo.entitytype > 0x00) then
            hasTarget = true;
        else
            hasTarget = false;
        end
    end

    if (pp.message_id == 6) then -- The <player> defeats <target>.
        statusType = 0x01;
        ----print(string.format('[DEBUG] [Message Basic] Msg: %d Actor: %s (%d/%d) Mob: %s (%d/%d) Desc: Defeated.', pp.message_id, actorInfo.name, actorInfo.id, actorInfo.index, targetInfo.name, targetInfo.id, targetInfo.index));
    elseif (pp.message_id == 20) then -- <target> falls to the ground.
        statusType = 0x01;
        ----print(string.format('[DEBUG] [Message Basic] Msg: %d Actor: %s (%d/%d) Mob: %s (%d/%d) Desc: Falls to the ground.', pp.message_id, actorInfo.name, actorInfo.id, actorInfo.index, targetInfo.name, targetInfo.id, targetInfo.index));
    elseif (pp.message_id == 558) then -- You defeated a designated target. (Progress: ../..)
        statusType = 0x11;
        ----print(string.format('[DEBUG] [Message Basic] Msg: %d Actor: %s (%d/%d) Mob: %s (%d/%d) Desc: Training progress.', pp.message_id, actorInfo.name, actorInfo.id, actorInfo.index, targetInfo.name, targetInfo.id, targetInfo.index));
    elseif (pp.message_id == 559) then -- You have successfully completed the training regime.
        statusType = 0x12;
        ----print(string.format('[DEBUG] [Message Basic] Msg: %d Actor: %s (%d/%d) Mob: %s (%d/%d) Desc: Training completed.', pp.message_id, actorInfo.name, actorInfo.id, actorInfo.index, targetInfo.name, targetInfo.id, targetInfo.index));
    else
        statusType = 0x00;
        ----print(string.format('[DEBUG] [Message Basic] *** Unhandled message! *** message_id: %d params: %d %d %d', pp.message_id, pp.param_1, pp.param_2, pp.param_3));
    end

    if (statusType > 0x00) then
        local mobitem;

        if (hasTarget) then
            mobitem = getMob(targetInfo.index, targetInfo.name);
            if (mobitem.is_tracking == nil) then
                mobitem.is_tracking = false;
            end

            lastmobitem = mobitem;
        else
            mobitem = lastmobitem;
        end

        if (statusType == 0x01) then
            -- No further ops
        elseif (statusType == 0x11) then
            if (mobitem ~= nil) then
                mobitem.is_tracking = true;
                mobitem.progress = pp.param_1;
                mobitem.total = pp.param_2;
            else
                print(string.format('MyValor: Missing mob.'));
            end
        elseif (statusType == 0x12) then
            for k, v in pairs(statusvalor.mobs) do
                if (mobitem.is_tracking) then
                    v.progress = 0;
                end
            end
        else
            print(string.format('Status type out of range: %d', statusType));
        end
    end
end

local function formatEntry(currenttime, mobName, progress, total)
    return color_entry(
        string.format(' %s (%s/%s) ',
            mobName,
            tostring(progress),
            tostring(total)),
        myvalor_config.colors.default_color);
end

ashita.register_event('command', function(cmd, nType)
    local args = cmd:GetArgs();

    if (#args > 0 and args[1] == '/valor')  then
        if (#args > 1)  then
            if (args[2] == 'reset')  then
                print('Resetting valor...');
                statusvalor = { };
                lastmobitem = nil;
                currentCreditMap = creditMap[MobInfoZoneId()];
            elseif (args[2] == 'debug')  then
                print('Debug valor...');
                if (statusvalor.mobs ~= nil) then
                    for k, v in pairs(statusvalor.mobs) do
                        print(tostring(k) .. ':' .. settings.JSON:encode(v));
                    end
                else
                    print('Empty!');
                end
            end
        end
    end
end);

ashita.register_event('incoming_packet', function(id, size, packet)
    -- 006 - The <player> defeats <target>.
    -- 558 - You defeated a designated target. (Progress: ../..)
    -- params: param_1 param_2 param_3
    -- params: 1       2       0       Progress: 1/2
    -- params: 2       2       0       Progress: 2/2
    -- params: 1       4       0       Progress: 1/4
    -- params: 2       4       0       Progress: 2/4
    -- params: 3       4       0       Progress: 3/4
    -- params: 4       4       0       Progress: 4/4
    -- 559 - You have successfully completed the training regime.
    -- 565 - <target> obtains .. gil.
    -- 566 - <target> obtains .. tabs. (Total: ..)
    -- 626 - Prowess boosted: increased combat and magic skill gain.
    -- 643 - ???

    __mobinfo_incoming_packet(id, size, packet);

    -- Check for zone-in packets..
    if (id == 0x0A) then
        statusvalor = { };
        lastmobitem = nil;
        currentCreditMap = creditMap[MobInfoZoneId()];
    end

    if (id == 0x0029) then -- Message Basic
        handleMessageBasicPacket(id, size, packet);
        return false;
    end

    return false;
end );

ashita.register_event('load', function()
    __mobinfo_load();

    -- Attempt to load the MyValor configuration..
    myvalor_config = settings:load(_addon.path .. 'settings/myvalor.json') or default_config;
    myvalor_config = table.merge(default_config, myvalor_config);

    -- Create our font object..
    local f = AshitaCore:GetFontManager():CreateFontObject( '__myvalor_addon' );
    f:SetBold( false );
    f:SetColor( myvalor_config.font.color );
    f:SetFont( myvalor_config.font.name, myvalor_config.font.size );
    f:SetPosition( myvalor_config.font.position[1], myvalor_config.font.position[2] );
    f:SetText( '' );
    f:SetVisibility( true );
    f:GetBackground():SetColor( myvalor_config.font.bgcolor );
    f:GetBackground():SetVisibility( myvalor_config.font.bgvisible );

    currentCreditMap = creditMap[MobInfoZoneId()];
end );

ashita.register_event('unload', function()
    local f = AshitaCore:GetFontManager():GetFontObject( '__myvalor_addon' );
    myvalor_config.font.position = { f:GetPositionX(), f:GetPositionY() };

    -- Ensure the settings folder exists..
    if (not file:dir_exists(_addon.path .. 'settings')) then
        file:create_dir(_addon.path .. 'settings');
    end

    -- Save the configuration..
    settings:save(_addon.path .. 'settings/myvalor.json', myvalor_config);

    -- Unload our font object..
    AshitaCore:GetFontManager():DeleteFontObject( '__myvalor_addon' );
end );

---------------------------------------------------------------------------------------------------
-- func: Render
-- desc: Called when our addon is rendered.
---------------------------------------------------------------------------------------------------
ashita.register_event('render', function()
    local currenttime = os.clock();

    -- Only render at 1/10s tick
    if ((lastrender + 0.1) < currenttime) then
        lastrender = currenttime;

        local f = AshitaCore:GetFontManager():GetFontObject( '__myvalor_addon' );
        local e = { }; -- Valor entries..

        if (statusvalor.mobs ~= nil) then
            local count = 0;
            local totalcount = 0;
            local s;

            for k, v in pairs(statusvalor.mobs) do
                local mob = v;

                if (mob.is_tracking) then
                    if (count < 32) then
                        s = formatEntry(currenttime, mob.name, mob.progress, mob.total);
                        if (s ~= nil) then
                            table.insert(e, s);
                            count = count + 1;
                        end
                    end
                end

                totalcount = totalcount + 1;
            end

            ------ DEBUG
            ----table.insert(e, string.format('   %d (%d) ', count, totalcount));
        end

        local output = table.concat( e, '\n' );
        f:SetText( output );
    end
end );
