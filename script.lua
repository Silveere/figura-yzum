-- vim: set foldmethod=marker ts=4 sw=4 :
-- from figura-protogen commit f3687a4
--- Initial definitions ---
-- Texture dimensions --
TEXTURE_WIDTH = 128
TEXTURE_HEIGHT = 128

-- utility functions -- {{{

--- Create a string representation of a table
--- @param o table
function dumpTable(o)
	if type(o) == 'table' then
		local s = '{ '
		local first_loop=true
		for k,v in pairs(o) do
			if not first_loop then
				s = s .. ', '
			end
			first_loop=false
			if type(k) ~= 'number' then k = '"'..k..'"' end
			s = s .. '['..k..'] = ' .. dumpTable(v)
		end
		return s .. '} '
	else
		return tostring(o)
	end
end

do
	local function format_any_value(obj, buffer)
		local _type = type(obj)
		if _type == "table" then
			buffer[#buffer + 1] = '{"'
			for key, value in next, obj, nil do
				buffer[#buffer + 1] = tostring(key) .. '":'
				format_any_value(value, buffer)
				buffer[#buffer + 1] = ',"'
			end
			buffer[#buffer] = '}' -- note the overwrite
		elseif _type == "string" then
			buffer[#buffer + 1] = '"' .. obj .. '"'
		elseif _type == "boolean" or _type == "number" then
			buffer[#buffer + 1] = tostring(obj)
		else
			buffer[#buffer + 1] = '"???' .. _type .. '???"'
		end
	end
	--- Dumps object as UNSAFE json, i stole this from stackoverflow so i could use json.tool to format it so it's easier to read
	function dumpJSON(obj)
		if obj == nil then return "null" else
			local buffer = {}
			format_any_value(obj, buffer)
			return table.concat(buffer)
		end
	end
end


---@param uv table
function UV(uv)
	return vectors.of({
	uv[1]/TEXTURE_WIDTH,
	uv[2]/TEXTURE_HEIGHT
	})
end


---@param inputstr string
---@param sep string
function splitstring (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end

---@param input string
function unstring(input)
	if input=="nil" then
		return nil
	elseif input == "true" or input == "false" then
		return input=="true"
	elseif tonumber(input) ~= nil then
		return tonumber(input)
	else
		return input
	end
end

---@param func function
---@param table table
function map(func, table)
	local t={}
	for k, v in pairs(table) do
		t[k]=func(v)
	end
	return t
end

---@param func function
---@param table table
function filter(func, table)
	local t={}
	for k, v in pairs(table) do
		if func(v) then
			t[k]=v
		end
	end
	return t
end

---@param tbl table
---@param val any
function has_value(tbl, val)
	for _, v in pairs(tbl) do
		if v==val then return true end
	end
	return false
end

--- Unordered reduction, only use when working with dictionaries and
--- execution order does not matter
---@param tbl table Table to reduce
---@param func function Function used to reduce table
---@param init any Initial operand for reduce function
function reduce(func, tbl, init)
	local result = init
	local first_loop = true
	for _, v in pairs(tbl) do
		if first_loop and init == nil then
			result=v
		else
			result = func(result, v)
		end
		first_loop=false
	end
	return result
end

--- Ordered reduction, does not work with dictionaries
---@param tbl table Table to reduce
---@param func function Function used to reduce table
---@param init any Initial operand for reduce function
function ireduce(func, tbl, init)
	local result = init
	local first_loop = true
	for _, v in ipairs(tbl) do
		if first_loop and init == nil then
			result=v
		else
			result = func(result, v)
		end
		first_loop=false
	end
	return result
end

--- Merge two tables. First table value takes precedence when conflict occurs.
---@param tb1 table
---@param tb2 table
function mergeTable(tb1, tb2)
	local t={}
	for k, v in pairs(tb1) do
		t[k]=v
	end
	for k, v in pairs(tb2) do
		if type(k)=="number" then
			table.insert(t, v)
		else
			if t[k]==nil then
				t[k]=v
			end
		end
	end
	return t
end

function debugPrint(var)
	print(dumpTable(var))
	return var
end

--- Recursively walk a model tree and return a table containing the group and each of its sub-groups
--- @param group table The group to recurse
--- @return table Resulting table
function recurseModelGroup(group)
	local t={}
	table.insert(t, group)
	if group.getType()=="GROUP" then
		for k, v in pairs(group.getChildren()) do
			for _, v2 in pairs(recurseModelGroup(v)) do
				table.insert(t, v2)
			end
		end
	end
	return t
end
-- }}}

-- Timer (not mine lol) -- {{{
do
	local timers = {}
	function wait(ticks,next)
		table.insert(timers, {t=world.getTime()+ticks,n=next})
	end
	function tick()
		for key,timer in pairs(timers) do
			if world.getTime() >= timer.t then
				timer.n()
				table.remove(timers,key)
			end
		end
	end
end

-- named timers (this one is mine but heavily based on the other) --
-- if timer is armed twice before expiring it will only be called once) --
do
	local timers = {}
	function namedWait(ticks, next, name)
		-- main difference, this will overwrite an existing timer with
		-- the same name
		timers[name]={t=world.getTime()+ticks,n=next}
	end
	function tick()
		for key, timer in pairs(timers) do
			if world.getTime() >= timer.t then
				timer.n()
				timers[key]=nil
			end
		end
	end
end

-- named cooldowns
do
	local timers={}
	function cooldown(ticks, name)
		if timers[name] == nil then
			timers[name]={t=world.getTime()+ticks}
			return true
		end
		return false
	end
	function tick()
		for key, timer in pairs(timers) do
			if world.getTime() >= timer.t then
				timers[key]=nil
			end
		end
	end
end

function rateLimit(ticks, next, name)
	if cooldown(ticks+1, name) then
		namedWait(ticks, next, name)
	end
end

-- }}}

-- syncState {{{
function syncState()
	ping.syncState(setLocalState())
end

function pmRefresh()
	rateLimit(1, PartsManager.refreshAll, "refreshAll")
end

function ping.syncState(tbl)
	for k, v in pairs(tbl) do
		local_state[k]=v
	end
	pmRefresh()
end
-- }}}

-- Math {{{
--- Sine function with period and amplitude
--- @param x number Input value
--- @param period number Period of sine wave
--- @param amp number Peak amplitude of sine wave
function wave(x, period, amp) return math.sin((2/period)*math.pi*(x%period))*amp end
function lerp(a, b, t) return a + ((b - a) * t) end
-- }}}

-- Master and local state variables -- {{{
-- Local State (these are copied by pings at runtime) --
local_state={}
old_state={}
-- master state variables and configuration (do not access within pings) --
do
	local is_host=client.isHost()
	local defaults={
		["armor_enabled"]=true,
		["vanilla_enabled"]=false,
		["vanilla_partial"]=false,
		["print_settings"]=false,
		["tail_enabled"]=true,
	}
	function setLocalState()
		if is_host then
			for k, v in pairs(skin_state) do
				local_state[k]=v
			end
		else
			for k, v in pairs(defaults) do
				if local_state[k] == nil then local_state[k]=v end
			end
		end
		return local_state
	end
	if is_host then
		local savedData=data.loadAll()
		if savedData == nil then
			for k, v in pairs(defaults) do
				data.save(k, v)
			end
			savedData=data.loadAll()
		end
		skin_state=mergeTable(
		map(unstring,data.loadAll()),
		defaults)
	else
		skin_state=defaults
	end
	setLocalState()
end

function printSettings()
	print("Settings:")
	for k, v in pairs(skin_state) do
		print(tostring(k)..": "..tostring(v))
	end
end
if skin_state.print_settings==true then
	printSettings()
end

function setState(name, state)
	if state == nil then
		skin_state[name]=not skin_state[name]
	else
		skin_state[name]=state
	end
	data.save(name, skin_state[name])
end

-- }}}

-- PartsManager -- {{{
do
	PartsManager={}
	local pm={}

	--- ensure part is initialized
	local function initPart(part)
		local part_key=tostring(part)
		if pm[part_key] == nil then
			pm[part_key]={}
		end
		pm[part_key].part=part
		if pm[part_key].functions == nil then
			pm[part_key].functions = {}
		end
		if pm[part_key].init==nil then
			pm[part_key].init="true"
		end
	end
	--- Add function to part in PartsManager.
	--- @param part table Any object with a setEnabled() method.
	--- @param func function Function to add to model part's function chain.
	--- @param init? boolean Default value for chain. Should only be set once, subsequent uses overwrite the entire chain's initial value.
	function PartsManager.addPartFunction(part, func, init)
		initPart(part)
		local part_key=tostring(part)
		if init ~= nil then
			pm[part_key].init=init
		end
		table.insert(pm[part_key]["functions"], func)
	end

	--- Set initial value for chain.
	--- @param part table Any object with a setEnabled() method.
	--- @param init? boolean Default value for chain. Should only be set once, subsequent uses overwrite the entire chain's initial value.
	function PartsManager.setInitialValue(part, init)
		assert(init~=nil)
		initPart(part)
		local part_key=tostring(part)
		pm[part_key].init=init
	end

	--- Set initial value for chain on all objects in table.
	--- @param group table A table containing objects with a setEnabled() method.
	--- @param init? boolean Default value for chain. Should only be set once, subsequent uses overwrite the entire chain's initial value.
	function PartsManager.setGroupInitialValue(group, init)
		assert(init~=nil)
		for _, v in pairs(group) do
			PartsManager.setInitialValue(v, init)
		end
	end

	--- Evaluate a part's chain to determine if it should be visible.
	--- @param part table An object managed by PartsManager.
	function PartsManager.evaluatePart(part)
		local part_key=tostring(part)
		assert(pm[part_key] ~= nil)

		local evalFunc=function(x, y) return y(x) end
		local init=pm[part_key].init
		return ireduce(evalFunc, pm[part_key].functions, true)
	end
	local evaluatePart=PartsManager.evaluatePart

	--- Refresh (enable or disable) a part based on the result of it's chain.
	--- @param part table An object managed by PartsManager.
	function PartsManager.refreshPart(part)
		local part_enabled=evaluatePart(part)
		part.setEnabled(part_enabled)
		return part_enabled
	end

	--- Refresh all parts managed by PartsManager.
	function PartsManager.refreshAll()
		for _, v in pairs(pm) do
			PartsManager.refreshPart(v.part)
		end
	end

	--- Add function to list of parts in PartsManager
	--- @param group table A table containing objects with a setEnabled() method.
	--- @param func function Function to add to each model part's function chain.
	--- @param default? boolean Default value for chain. Should only be set once, subsequent uses overwrite the entire chain's initial value.
	function PartsManager.addPartGroupFunction(group, func, default)
		for _, v in ipairs(group) do
			PartsManager.addPartFunction(v, func, default)
		end
	end
end
-- }}}

-- UVManager {{{
do
	local mt={}
	UVManager = {
		step=vectors.of{u=0, v=0},
		offset=vectors.of{u=0, v=0},
		positions={}
	}
	mt.__index=UVManager
	function UVManager.new(self, step, offset, positions)
		local t={}
		if step ~= nil then t.step=vectors.of(step) end
		if offset ~= nil then t.offset=vectors.of(offset) end
		if positions ~= nil then t.positions=positions end
		t=setmetatable(t, mt)
		return t
	end
	function UVManager.getUV(self, input)
		local vec={}
		local stp=self.step
		local offset=self.offset
		if type(input) == "string" then
			if self.positions[input] == nil then return nil end
			vec=vectors.of(self.positions[input])
		else
			vec=vectors.of(input)
		end
		local u=offset.u+(vec.u*stp.u)
		local v=offset.v+(vec.v*stp.v)
		return UV{u, v}
	end
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
TAIL_BONES={model.Body_Tail, model.Body_Tail.Body_Tail2, model.Body_Tail.Body_Tail2.Body_Tail3, model.Body_Tail.Body_Tail2.Body_Tail3.Body_Tail4}

TAIL_ROT={vectors.of{37.5, 0, 0}, vectors.of{-17.5, 0, 0}, vectors.of{-17.5, 0, 0}, vectors.of{-15, 0, 0}}
-- }}}

-- Enable commands -- {{{
chat_prefix="$"
chat.setFiguraCommandPrefix(chat_prefix)
function onCommand(input)
	local pfx=chat_prefix
	input=splitstring(input)
	if input[1] == chat_prefix .. "vanilla" then
		setVanilla()
		print("Vanilla skin is now " .. (skin_state.vanilla_enabled and "enabled" or "disabled"))
	end
	if input[1] == chat_prefix .. "toggle_custom" then
		for key, value in pairs(model) do
			value.setEnabled(not value.getEnabled())
		end
	end
	if input[1] == chat_prefix .. "toggle_outer" then
		for k, v in pairs(VANILLA_GROUPS.OUTER) do
			v.setEnabled(not v.getEnabled())
		end
	end
	if input[1] == chat_prefix .. "toggle_inner" then
		for k, v in pairs(VANILLA_GROUPS.INNER) do
			v.setEnabled(not v.getEnabled())
		end
	end
	if input[1] == chat_prefix .. "test_expression" then
		setExpression(input[2], input[3])
		print(input[2] .. " " .. input[3])
	end
	if input[1] == chat_prefix .. "snore" then
		if input[2] == "toggle" or #input==1 then
			setSnoring()
			log("Snoring is now " .. (skin_state.snore_enabled and "enabled" or "disabled"))
		end
	end
	if input[1] == chat_prefix .. "armor" then
		setArmor()
		log("Armor is now " .. (skin_state.armor_enabled and "enabled" or "disabled"))
	end
	if input[1] == chat_prefix .. "settings" then
		if #input==1 then
			printSettings()
		elseif #input==2 then
			log(tostring(skin_state[input[2]]))
		elseif #input==3 then
			if skin_state[input[2]] ~= nil then
				setState(input[2], unstring(input[3]))
				log(tostring(input[2]) .. " is now " .. tostring(skin_state[input[2]]))
				syncState()
			else
				log(tostring(input[2]) .. ": no such setting")
			end
		end
	end
	if input[1] == chat_prefix .. "pv" then
		setState("vanilla_partial")
		syncState()
	end
end
--}}}

-- PartsManager Rules {{{
do
	local can_modify_vanilla=meta.getCanModifyVanilla()
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

-- Action Wheel {{{
do
	local slot_1_item = item_stack.createItem("minecraft:netherite_helmet")
	action_wheel.SLOT_1.setTitle('Toggle Armor')
	action_wheel.SLOT_1.setFunction(function() setArmor() end)
	action_wheel.SLOT_1.setItem(slot_1_item)
end


function setArmor()
	setState("armor_enabled")
	syncState()
end
-- }}}

function player_init()
	for k, v in pairs(reduce(mergeTable, map(recurseModelGroup, model))) do
		v.setEnabled(true)
	end
	setLocalState()
	syncState()
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
		TAIL_BONES[k].setRot(vectors.of{TAIL_ROT[k].x + wave(val-cascade, per_x, 3), TAIL_ROT[k].y + wave(val-cascade, per_y, 17.5), TAIL_ROT[k].z})
	end
end

function tick()
	if not refreshed then
		cooldown(1, "refreshAll")
		PartsManager.refreshAll()
		refreshed=true
	end

	if world.getTime() % (20*10) == 0 then
		syncState()
	end
	animateTick()
end

function render(delta)
	animateTail(lerp(old_state.anim_cycle, anim_cycle, delta))
end
