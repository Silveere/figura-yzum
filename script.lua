-- vim: set foldmethod=marker ts=4 sw=4 :
-- from figura-protogen commit f3687a4
--- Initial definitions ---
-- rewrite compat
model=models.player_model
armor_model={
	["BOOTS"]=vanilla_model.BOOTS,
	["LEGGINGS"]=vanilla_model.LEGGINGS,
	["CHESTPLATE"]=vanilla_model.CHESTPLATE,
	["HELMET"]=vanilla_model.HELMET
}
ping=pings

-- Texture dimensions --
TEXTURE_WIDTH = 128
TEXTURE_HEIGHT = 128

PartsManager=require("nulllib.PartsManager")
UVManager=require("nulllib.UVManager")
logging=require("nulllib.logging")
nmath=require("nulllib.math")
timers=require("nulllib.timers")
util=require("nulllib.util")
sharedstate=require("nulllib.sharedstate")
sharedconfig=require("nulllib.sharedconfig")

wave=nmath.wave
lerp=math.lerp

-- Master and local state variables -- {{{
-- Local State (these are copied by pings at runtime) --
local_state={}
old_state={}
-- master state variables and configuration (do not access within pings) --
do
	local is_host=host:isHost()
	local defaults={
		["armor_enabled"]=true,
		["vanilla_enabled"]=false,
		["vanilla_partial"]=false,
		["print_settings"]=false,
		["tail_enabled"]=true,
	}
end

function printSettings()
	print("Settings:")
	printTable(sharedconfig.load())
end
if sharedconfig.load("print_settings") then
	printSettings()
end

-- }}}

-- Part groups {{{
VANILLA_GROUPS={
	["HEAD"]={vanilla_model.HEAD, vanilla_model.HAT},
	["TORSO"]={vanilla_model.TORSO, vanilla_model.JACKET},
	["LEFT_ARM"]={vanilla_model.LEFT_ARM, vanilla_model.LEFT_SLEEVE},
	["RIGHT_ARM"]={vanilla_model.RIGHT_ARM, vanilla_model.RIGHT_SLEEVE},
	["LEFT_LEG"]={vanilla_model.LEFT_LEG, vanilla_model.LEFT_PANTS_LEG},
	["RIGHT_LEG"]={vanilla_model.RIGHT_LEG, vanilla_model.RIGHT_PANTS_LEG},
	["OUTER"]={ vanilla_model.HAT, vanilla_model.JACKET, vanilla_model.LEFT_SLEEVE, vanilla_model.RIGHT_SLEEVE, vanilla_model.LEFT_PANTS_LEG, vanilla_model.RIGHT_PANTS_LEG },
	["INNER"]={ vanilla_model.HEAD, vanilla_model.TORSO, vanilla_model.LEFT_ARM, vanilla_model.RIGHT_ARM, vanilla_model.LEFT_LEG, vanilla_model.RIGHT_LEG },
	["ALL"]={},
	["ARMOR"]={}
}

for _, v in pairs(VANILLA_GROUPS.INNER) do table.insert(VANILLA_GROUPS.ALL,v) end
for _, v in pairs(VANILLA_GROUPS.OUTER) do table.insert(VANILLA_GROUPS.ALL,v) end
for _, v in pairs(armor_model) do table.insert(VANILLA_GROUPS.ARMOR, v) end

MAIN_GROUPS={model.Head, model.RightArm, model.LeftArm, model.RightLeg, model.LeftLeg, model.Body } -- RightArm LeftArm RightLeg LeftLeg Body Head
TAIL_BONES={model.Body_Tail, model.Body_Tail.Tail2, model.Body_Tail.Tail2.Tail3, model.Body_Tail.Tail2.Tail3.Tail4}

TAIL_ROT={vec( 37.5, 0, 0 ), vec( -17.5, 0, 0 ), vec( -17.5, 0, 0 ), vec( -15, 0, 0 )}
-- }}}

-- -- Enable commands -- {{{
-- chat_prefix="$"
-- chat.setFiguraCommandPrefix(chat_prefix)
-- function onCommand(input)
-- 	local pfx=chat_prefix
-- 	input=splitstring(input)
-- 	if input[1] == chat_prefix .. "vanilla" then
-- 		setVanilla()
-- 		print("Vanilla skin is now " .. (skin_state.vanilla_enabled and "enabled" or "disabled"))
-- 	end
-- 	if input[1] == chat_prefix .. "toggle_custom" then
-- 		for key, value in pairs(model) do
-- 			value.setEnabled(not value.getEnabled())
-- 		end
-- 	end
-- 	if input[1] == chat_prefix .. "toggle_outer" then
-- 		for k, v in pairs(VANILLA_GROUPS.OUTER) do
-- 			v.setEnabled(not v.getEnabled())
-- 		end
-- 	end
-- 	if input[1] == chat_prefix .. "toggle_inner" then
-- 		for k, v in pairs(VANILLA_GROUPS.INNER) do
-- 			v.setEnabled(not v.getEnabled())
-- 		end
-- 	end
-- 	if input[1] == chat_prefix .. "test_expression" then
-- 		setExpression(input[2], input[3])
-- 		print(input[2] .. " " .. input[3])
-- 	end
-- 	if input[1] == chat_prefix .. "snore" then
-- 		if input[2] == "toggle" or #input==1 then
-- 			setSnoring()
-- 			log("Snoring is now " .. (skin_state.snore_enabled and "enabled" or "disabled"))
-- 		end
-- 	end
-- 	if input[1] == chat_prefix .. "armor" then
-- 		setArmor()
-- 		log("Armor is now " .. (skin_state.armor_enabled and "enabled" or "disabled"))
-- 	end
-- 	if input[1] == chat_prefix .. "settings" then
-- 		if #input==1 then
-- 			printSettings()
-- 		elseif #input==2 then
-- 			log(tostring(skin_state[input[2]]))
-- 		elseif #input==3 then
-- 			if skin_state[input[2]] ~= nil then
-- 				setState(input[2], unstring(input[3]))
-- 				log(tostring(input[2]) .. " is now " .. tostring(skin_state[input[2]]))
-- 				syncState()
-- 			else
-- 				log(tostring(input[2]) .. ": no such setting")
-- 			end
-- 		end
-- 	end
-- 	if input[1] == chat_prefix .. "pv" then
-- 		setState("vanilla_partial")
-- 		syncState()
-- 	end
-- end
-- --}}}

-- PartsManager Rules {{{
do
	local can_modify_vanilla=avatar:canEditVanillaModel()
	local function forceVanilla()
		return not can_modify_vanilla or local_state.vanilla_enabled
	end

	local function vanillaPartial()
		return not local_state.vanilla_enabled and local_state.vanilla_partial
	end


	local PM=PartsManager

	local vanilla_partial_disabled=MAIN_GROUPS

	-- Vanilla state
	PM.addPartGroupFunction(VANILLA_GROUPS.ALL, function() return false end)
	PM.addPartGroupFunction(VANILLA_GROUPS.ALL, function(last) return last or forceVanilla() end)

	PM.addPartGroupFunction(VANILLA_GROUPS.ALL, function(last) return last or vanillaPartial() end)

	-- disable cape if tail enabled
	PM.addPartFunction(vanilla_model.CAPE, function(last) return last and not local_state.tail_enabled end)

	-- Custom state
	PM.addPartGroupFunction(vanilla_partial_disabled, function(last) return last and not vanillaPartial() end)
	PM.addPartGroupFunction(MAIN_GROUPS, function(last) return last and not forceVanilla() end)

	-- enable tail
	PM.addPartFunction(model.Body_Tail, function(last) return last and local_state.tail_enabled end)

	-- Armor state
	PM.addPartGroupFunction(VANILLA_GROUPS.ARMOR, function(last) return last and local_state.armor_enabled end)


end
-- }}}

-- -- Action Wheel {{{
-- do
-- 	local slot_1_item = item_stack.createItem("minecraft:netherite_helmet")
-- 	action_wheel.SLOT_1.setTitle('Toggle Armor')
-- 	action_wheel.SLOT_1.setFunction(function() setArmor() end)
-- 	action_wheel.SLOT_1.setItem(slot_1_item)
-- end


function setArmor()
	sharedconfig.save("armor_enabled", not sharedconfig.load("armor_enabled"))
end
-- }}}

function player_init()
	-- for k, v in pairs(reduce(mergeTable, map(recurseModelGroup, model))) do
	-- 	v.setEnabled(true)
	-- end
	-- syncState()
	events.ENTITY_INIT:remove("player_init")
end

events.ENTITY_INIT:register(function() return player_init() end, "player_init")

if avatar:canEditVanillaModel() then
	vanilla_model.PLAYER:setVisible(false)
else
	model:setVisible(false)
end

anim_tick=0
anim_cycle=0
old_state.anim_cycle=0
function animateTick()
	anim_tick = anim_tick + 1
	old_state.anim_cycle=anim_cycle
	anim_cycle=anim_cycle+1
end

function animateTail(val)
	local per_y=20*4
	local per_x=20*6
	for k, v in pairs(TAIL_BONES) do
		local cascade=(k-1)*12
		TAIL_BONES[k]:setRot(vec( TAIL_ROT[k].x + wave(val-cascade, per_x, 3), TAIL_ROT[k].y + wave(val-cascade, per_y, 17.5), TAIL_ROT[k].z ))
	end
end

function tick()
	if world.getTime() % (20*10) == 0 then
		-- TODO fix
		-- syncState()
	end
	animateTick()

	-- TODO fix
	-- doPmRefresh()
end
events.TICK:register(function() if player then tick() end end, "main_tick")

function render(delta)
	animateTail(lerp(old_state.anim_cycle, anim_cycle, delta))
end
events.RENDER:register(function(delta) if player then render(delta) end end, "main_render")
