local share_bones_time = tonumber(minetest.settings:get("share_bones_time")) or 1200

local function serializeContents(contents)
   if not contents then return "" end

   local tabs = {}
   for i, stack in ipairs(contents) do
      tabs[i] = stack and stack:to_table() or ""
   end

   return minetest.serialize(tabs)
end

local function deserializeContents(data)
   if not data or data == "" then return nil end
   local tabs = minetest.deserialize(data)
   if not tabs or type(tabs) ~= "table" then return nil end

   local contents = {}
   for i, tab in ipairs(tabs) do
      contents[i] = ItemStack(tab)
   end

   return contents
end

minetest.register_entity("bones_entity:entity", {
	hp_max = 1,
	physical = false,
	weight = 5,
	collisionbox = {-0.3, -1, -0.3, 0.3, -.4, 0.3},
	visual = "mesh",
	mesh = "character.b3d",
	textures = {"invisible.png"},
	is_visible = true,
	makes_footstep_sound = false,
    automatic_rotate = false,
    on_activate = function(self, staticdata, dtime_s)
		if not self.owner then
			local deserialized = minetest.deserialize(staticdata)
			if deserialized then
				self.inv = deserializeContents(deserialized.inv)
				if deserialized.owner then
					self.owner = deserialized.owner
				end
				if deserialized.expiretime then
					self.time = deserialized.expiretime
					if self.time < os.time() then
						self.object:set_properties({infotext = self.owner.."'s old bones"})
					else
						self.object:set_properties({infotext = self.owner.."'s fresh bones"})
						minetest.after(self.time-os.time(), function(self) 
							self.object:set_properties({infotext = self.owner.."'s old bones"})
						end, self)
					end
				end
				local inv = minetest.create_detached_inventory("bones_"..self.owner, {})
				inv:set_size("main", 8 * 6)
				inv:set_list("main",self.inv)
				if inv:is_empty("main") then
					self.object:remove()
				end
			end
			self.object:set_armor_groups({immortal = 1})
			if deserialized.mesh and deserialized.textures and deserialized.yaw then
				self.mesh = deserialized.mesh
				self.textures = deserialized.textures
				self.yaw = deserialized.yaw
				self.object:set_properties({mesh = deserialized.mesh, textures = deserialized.textures})
				self.object:set_yaw(deserialized.yaw)
				self.object:set_animation({x=162,y=167}, 1)
			end
		end
    end,
	get_staticdata = function(self)
		return minetest.serialize({owner = self.owner, expiretime = self.time, mesh = self.mesh, textures = self.textures, yaw = self.yaw, inv = serializeContents(self.inv)})
	end,
    on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		local name = puncher:get_player_name()
		if name ~= self.owner and self.time > os.time() and not minetest.check_player_privs(name, "protection_bypass") then return end
		
		local player_inv = puncher:get_inventory()
		local has_space = true
		local inv = minetest.create_detached_inventory("bones_"..self.owner, {})
		inv:set_size("main", 8 * 6)
		inv:set_list("main",self.inv)
		--The MIT License (MIT) (Following 12 lines)
		--Copyright (C) 2012-2016 PilzAdam
		--Copyright (C) 2012-2016 Various Minetest developers and contributors
		for i = 1, inv:get_size("main") do
			local stk = inv:get_stack("main", i)
			if player_inv:room_for_item("main", stk) then
				inv:set_stack("main", i, nil)
				player_inv:add_item("main", stk)
			else
				has_space = false
				break
			end
		end
		-- remove bones if player emptied them
		if has_space then
			self.object:remove()
		else
			self.inv = inv:get_list("main")
		end
    end,
    on_rightclick = function(self, clicker)
		local name = clicker:get_player_name()
		local inventory = minetest.create_detached_inventory("bones_"..name, {
			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
				return 0
			end,
			allow_put = function(inv, listname, index, stack, player)
				return 0
			end,
			allow_take = function(inv, listname, index, stack, player)
				local name = player:get_player_name()
				if name == self.owner or self.time < os.time() or minetest.check_player_privs(name, "protection_bypass") then
					return stack:get_count()
				end
				return 0
			end,
			on_take = function(inv, listname, index, stack, player)
				self.inv = inv:get_list("main")
				if inv:is_empty("main") then
					self.object:remove()
				end
			end,
		})
		inventory:set_size("main", 48)
		local templist = table.copy(self.inv)
		inventory:set_list("main", templist)
		local formspec =
			   "size[12,9]"..
			   "list[detached:bones_"..name..";main;0,0;12,4;]"..
			   "list[current_player;main;2,5;8,4;]"
		minetest.show_formspec(name, "bones_inv", formspec)
    end
})
minetest.register_on_dieplayer(function(player)
	local pos = player:get_pos()
	local player_inv = player:get_inventory()
	if player_inv:is_empty("main") and
		player_inv:is_empty("craft") then
		return
	end
	local inv = minetest.create_detached_inventory("bones_"..player:get_player_name(), {})
	--The MIT License (MIT) (Following 14 lines)
	--Copyright (C) 2012-2016 PilzAdam
	--Copyright (C) 2012-2016 Various Minetest developers and contributors
	inv:set_size("main", 8 * 6)
	inv:set_list("main", player_inv:get_list("main"))

	for i = 1, player_inv:get_size("craft") do
		local stack = player_inv:get_stack("craft", i)
		if inv:room_for_item("main", stack) then
			inv:add_item("main", stack)
		else
			--drop if no space left
			drop(pos, stack)
		end
	end
	pos.y = pos.y + 1
	local props = player:get_properties()
	local yaw = player:get_look_horizontal()
	local e = minetest.add_entity(pos, "bones_entity:entity", minetest.serialize({owner = player:get_player_name(), expiretime = os.time() + share_bones_time, mesh = props.mesh, textures = props.textures, yaw = yaw, inv = serializeContents(inv:get_list("main"))}))

	player_inv:set_list("main", {})
	player_inv:set_list("craft", {})
end)