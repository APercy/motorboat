--
-- constants
--
local LONGIT_DRAG_FACTOR = 0.13*0.13
local LATER_DRAG_FACTOR = 2.0

gravity = tonumber(minetest.settings:get("movement_gravity")) or 9.8

local colors ={
    black='#2b2b2b',
    blue='#0063b0',
    brown='#8c5922',
    cyan='#07B6BC',
    dark_green='#567a42',
    dark_grey='#6d6d6d',
    green='#4ee34c',
    grey='#9f9f9f',
    magenta='#ff0098',
    orange='#ff8b0e',
    pink='#ff62c6',
    red='#dc1818',
    violet='#a437ff',
    white='#FFFFFF',
    yellow='#ffe400',
}

dofile(minetest.get_modpath("motorboat") .. DIR_DELIM .. "motorboat_control.lua")
dofile(minetest.get_modpath("motorboat") .. DIR_DELIM .. "motorboat_fuel_management.lua")


last_time = minetest.get_us_time()
local random = math.random

--
-- helpers and co.
--

local creative_exists = minetest.global_exists("creative")

local function get_hipotenuse_value(point1, point2)
    return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

local function dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

local function sign(n)
	return n>=0 and 1 or -1
end

local function minmax(v,m)
	return math.min(math.abs(v),m)*sign(v)
end

--painting
local function paint(self, colstr)
    if colstr then
        self.color = colstr
        local l_textures = self.initial_properties.textures
        for _, texture in ipairs(l_textures) do
            local i,indx = texture:find('motorboat_painting.png')
            if indx then
                l_textures[_] = "motorboat_painting.png^[multiply:".. colstr
            end
        end
	    self.object:set_properties({textures=l_textures})
    end
end

-- destroy the boat
local function destroy(self)
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end

    if self.driver_name then
        -- detach the driver first (puncher must be driver)
        puncher:set_detach()
        puncher:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player_api.player_attached[name] = nil
        -- player should stand again
        player_api.set_animation(puncher, "stand")
        self.driver_name = nil
    end

    local pos = self.object:get_pos()
    if self.pointer then self.pointer:remove() end
    if self.engine then self.engine:remove() end

    self.object:remove()

    pos.y=pos.y+2
    for i=1,7 do
	    minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'default:steel_ingot')
    end

    for i=1,7 do
	    minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'default:mese_crystal')
    end

    --minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'motorboat:boat')
    minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'default:diamond')

    local total_biofuel = math.floor(self.energy) - 1
    for i=0,total_biofuel do
        minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'biofuel:biofuel')
    end
end


--
-- entity
--

minetest.register_entity('motorboat:engine',{
initial_properties = {
	physical = false,
	collide_with_objects=false,
	pointable=false,
	visual = "mesh",
	mesh = "engine.b3d",
	textures = {"motorboat_helice.png", "motorboat_black.png",},
	},
	
on_activate = function(self,std)
	self.sdata = minetest.deserialize(std) or {}
	if self.sdata.remove then self.object:remove() end
end,
	
get_staticdata=function(self)
  self.sdata.remove=true
  return minetest.serialize(self.sdata)
end,
	
})

minetest.register_entity("motorboat:boat", {
	initial_properties = {
	    physical = true,
	    collisionbox = {-0.6, -0.6, -0.6, 0.6, 1.2, 0.6}, --{-1,0,-1, 1,0.3,1},
	    selectionbox = {-1,0,-1, 1,1,1},
	    visual = "mesh",
	    mesh = "hull.b3d",
        textures = {"motorboat_black.png", "motorboat_panel.png", "motorboat_glass.png", "motorboat_hull.png", "default_junglewood.png", "motorboat_painting.png"},
    },
    textures = {},
	driver_name = nil,
	sound_handle = nil,
    energy = 0.001,
    owner = "",
    static_save = true,
    infotext = "A nice boat",
    lastvelocity = vector.new(),
    hp = 50,
    color = "#07B6BC",
    rudder_angle = 0,
    timeout = 0;
    buoyancy = 0.35,
    max_hp = 50,
    engine_running = false,
    anchored = true,
    --water_drag = 0,

    get_staticdata = function(self) -- unloaded/unloads ... is now saved
        return minetest.serialize({
            stored_energy = self.energy,
            stored_owner = self.owner,
            stored_hp = self.hp,
            stored_color = self.color,
            stored_anchor = self.anchored,
        })
    end,

	on_activate = function(self, staticdata, dtime_s)
        if staticdata ~= "" and staticdata ~= nil then
            local data = minetest.deserialize(staticdata) or {}
            self.energy = data.stored_energy
            self.owner = data.stored_owner
            self.hp = data.stored_hp
            self.color = data.stored_color
            self.anchored = data.stored_anchor
            --minetest.debug("loaded: ", self.energy)
        end

        paint(self, self.color)
        local pos = self.object:get_pos()

	    local engine=minetest.add_entity(pos,'motorboat:engine')
	    engine:set_attach(self.object,'',{x=0,y=6,z=-21},{x=0,y=0,z=0})
		-- set the animation once and later only change the speed
        engine:set_animation({x = 1, y = 8}, 0, 0, true)
	    self.engine = engine

	    local pointer=minetest.add_entity(pos,'motorboat:pointer')
        local energy_indicator_angle = get_pointer_angle(self.energy)
	    pointer:set_attach(self.object,'',{x=0,y=5.52451,z=5.89734},{x=0,y=0,z=energy_indicator_angle})
	    self.pointer = pointer

		self.object:set_armor_groups({immortal=1})

		--self.object:set_acceleration(vector.multiply(vector_up, -gravity))
        mobkit.actfunc(self, staticdata, dtime_s)

	end,

	on_step = function(self, dtime)
        mobkit.stepfunc(self, dtime)

        local accel_y = self.object:get_acceleration().y
        local rotation = self.object:get_rotation()
        local yaw = rotation.y
		local newyaw=yaw
        local pitch = rotation.x
        local newpitch = pitch
		local roll = rotation.z
		local newroll=roll

        local hull_direction = minetest.yaw_to_dir(yaw)
        local nhdir = {x=hull_direction.z,y=0,z=-hull_direction.x}		-- lateral unit vector
        local velocity = self.object:get_velocity()

        local longit_speed = dot(velocity,hull_direction)
        local longit_drag = vector.multiply(hull_direction,longit_speed*longit_speed*LONGIT_DRAG_FACTOR*-1*sign(longit_speed))
		local later_speed = dot(velocity,nhdir)
		local later_drag = vector.multiply(nhdir,later_speed*later_speed*LATER_DRAG_FACTOR*-1*sign(later_speed))
        local accel = vector.add(longit_drag,later_drag)

        local vel = self.object:get_velocity()

        local is_attached = false
        if self.owner then
            local player = minetest.get_player_by_name(self.owner)
            
            if player then
                local player_attach = player:get_attach()
                if player_attach then
                    if player_attach == self.object then is_attached = true end
                end
            end
        end

		if is_attached then
            local impact = get_hipotenuse_value(vel, self.last_vel)
            if impact > 1 then
                --self.damage = self.damage + impact --sum the impact value directly to damage meter
                local curr_pos = self.object:get_pos()
                minetest.sound_play("collision", {
                    to_player = self.driver_name,
	                --pos = curr_pos,
	                --max_hear_distance = 5,
	                gain = 1.0,
                    fade = 0.0,
                    pitch = 1.0,
                })
                --[[if self.damage > 100 then --if acumulated damage is greater than 100, adieu
                    destroy(self)   
                end]]--
            end

            --control
			accel = motorboat_control(self, dtime, hull_direction, longit_speed, longit_drag, later_speed, later_drag, accel) or vel
        else
            if self.sound_handle ~= nil then
	            minetest.sound_stop(self.sound_handle)
	            self.sound_handle = nil
            end
		end

        self.engine:set_attach(self.object,'',{x=0,y=6,z=-21},{x=0,y=self.rudder_angle,z=0})

		if math.abs(self.rudder_angle)>5 then 
            local turn_rate = math.rad(24)
			newyaw = yaw + self.dtime*(1 - 1 / (math.abs(longit_speed) + 1)) * self.rudder_angle / 30 * turn_rate * sign(longit_speed)
		end

        -- calculate energy consumption --
        ----------------------------------
        if self.energy > 0 and self.engine_running then
            local zero_reference = vector.new()
            local acceleration = get_hipotenuse_value(accel, zero_reference)
            local consumed_power = acceleration/6000
            self.energy = self.energy - consumed_power;

            local energy_indicator_angle = get_pointer_angle(self.energy)
            if self.pointer:get_luaentity() then
                self.pointer:set_attach(self.object,'',{x=0,y=5.52451,z=5.89734},{x=0,y=0,z=energy_indicator_angle})
            else
                --in case it have lost the entity by some conflict
                self.pointer=minetest.add_entity({x=0,y=5.52451,z=5.89734},'motorboat:pointer')
                self.pointer:set_attach(self.object,'',{x=0,y=5.52451,z=5.89734},{x=0,y=0,z=energy_indicator_angle})
            end
        end
        if self.energy <= 0 and self.engine_running then
            self.engine_running = false
            if self.sound_handle then minetest.sound_stop(self.sound_handle) end
		    self.engine:set_animation_frame_speed(0)
        end
        ----------------------------
        -- end energy consumption --

        --roll adjust
        ---------------------------------
		local sdir = minetest.yaw_to_dir(newyaw)
		local snormal = {x=sdir.z,y=0,z=-sdir.x}	-- rightside, dot is negative
		local prsr = dot(snormal,nhdir)
        local rollfactor = -10
        newroll = (prsr*math.rad(rollfactor))*later_speed
        --minetest.chat_send_all('newroll: '.. newroll)
        ---------------------------------
        -- end roll

		local bob = minmax(dot(accel,hull_direction),0.8)	-- vertical bobbing

		if self.isinliquid then
			accel.y = accel_y + bob
			newpitch = velocity.y * math.rad(6)
			self.object:set_acceleration(accel)
		end

		if newyaw~=yaw or newpitch~=pitch or newroll~=roll then self.object:set_rotation({x=newpitch,y=newyaw,z=newroll}) end

        --saves last velocy for collision detection (abrupt stop)
        self.last_vel = self.object:get_velocity()
	end,

	on_punch = function(self, puncher, ttime, toolcaps, dir, damage)
		if not puncher or not puncher:is_player() then
			return
		end
		local name = puncher:get_player_name()
        if self.owner and self.owner ~= name and self.owner ~= "" then return end
        if self.owner == nil then
            self.owner = name
        end
        	
        if self.driver_name and self.driver_name ~= name then
			-- do not allow other players to remove the object while there is a driver
			return
		end

        local touching_ground, liquid_below = check_node_below(self.object)
        
        local is_attached = false
        if puncher:get_attach() == self.object then is_attached = true end

        local itmstck=puncher:get_wielded_item()
        local item_name = ""
        if itmstck then item_name = itmstck:get_name() end

        if is_attached == true and item_name == "biofuel:biofuel" and self.engine_running == false then
            --refuel
            motorboat_load_fuel(self, puncher:get_player_name())
        end

        if is_attached == false then

            -- deal with painting or destroying
		    if itmstck then
			    local _,indx = item_name:find('dye:')
			    if indx then

                    --lets paint!!!!
				    local color = item_name:sub(indx+1)
				    local colstr = colors[color]
                    --minetest.chat_send_all(color ..' '.. dump(colstr))
				    if colstr then
                        paint(self, colstr)
					    itmstck:set_count(itmstck:get_count()-1)
					    puncher:set_wielded_item(itmstck)
				    end
                    -- end painting

			    else -- deal damage
				    if not self.driver and toolcaps and toolcaps.damage_groups and toolcaps.damage_groups.fleshy then
					    --mobkit.hurt(self,toolcaps.damage_groups.fleshy - 1)
					    --mobkit.make_sound(self,'hit')
                        self.hp = self.hp - 10
                        minetest.sound_play("collision", {
	                        object = self.object,
	                        max_hear_distance = 5,
	                        gain = 1.0,
                            fade = 0.0,
                            pitch = 1.0,
                        })
				    end
			    end
            end

            if self.hp <= 0 then
                destroy(self)
            end

        end
        
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end

		local name = clicker:get_player_name()
        if self.owner and self.owner ~= name and self.owner ~= "" then return end
        if self.owner == "" then
            self.owner = name
        end

		if name == self.driver_name then
            self.engine_running = false

			-- driver clicked the object => driver gets off the vehicle
			self.driver_name = nil
			-- sound and animation
            if self.sound_handle then
                minetest.sound_stop(self.sound_handle)
                self.sound_handle = nil
            end
			
			self.engine:set_animation_frame_speed(0)

            -- detach the player
		    clicker:set_detach()
		    player_api.player_attached[name] = nil
		    clicker:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
		    player_api.set_animation(clicker, "stand")
		    self.driver = nil
            self.object:set_acceleration(vector.multiply(vector_up, -gravity))
        
		elseif not self.driver_name then
	        -- no driver => clicker is new driver
	        self.driver_name = name

            -- temporary------
            self.hp = 50 -- why? cause I can desist from destroy
            ------------------

	        -- attach the driver
	        clicker:set_attach(self.object, "", {x = 0, y = 5, z = -6}, {x = 0, y = 0, z = 0})
	        clicker:set_eye_offset({x = 0, y = 0, z = -5.5}, {x = 0, y = 0, z = -5.5})
	        player_api.player_attached[name] = true
	        -- make the driver sit
	        minetest.after(0.2, function()
		        local player = minetest.get_player_by_name(name)
		        if player then
			        player_api.set_animation(player, "sit")
		        end
	        end)
	        -- disable gravity
	        self.object:set_acceleration(vector.new())
		end
	end,
})

--
-- items
--

-- engine
minetest.register_craftitem("motorboat:engine",{
	description = "Boat engine",
	inventory_image = "motorboat_engine_inv.png",
})
-- hull
minetest.register_craftitem("motorboat:hull",{
	description = "Hull of the boat",
	inventory_image = "motorboat_hull_inv.png",
})


-- boat
minetest.register_craftitem("motorboat:boat", {
	description = "Motorboat",
	inventory_image = "motorboat_inv.png",
    liquids_pointable = true,

	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return
		end
        
        local pointed_pos = pointed_thing.under
        local node_below = minetest.get_node(pointed_pos).name
        local nodedef = minetest.registered_nodes[node_below]
        if nodedef.liquidtype ~= "none" then
			pointed_pos.y=pointed_pos.y+0.2
			local boat = minetest.add_entity(pointed_pos, "motorboat:boat")
			if boat and placer then
                local ent = boat:get_luaentity()
                local owner = placer:get_player_name()
                ent.owner = owner
				boat:set_yaw(placer:get_look_horizontal())
				itemstack:take_item()
			end
        end

		return itemstack
	end,
})

--
-- crafting
--

if minetest.get_modpath("default") then
	minetest.register_craft({
		output = "motorboat:engine",
		recipe = {
			{"",                    "default:steel_ingot", ""},
			{"default:steel_ingot", "default:mese_block",  "default:steel_ingot"},
			{"",                    "default:steel_ingot", "default:diamond"},
		}
	})
	minetest.register_craft({
		output = "motorboat:hull",
		recipe = {
			{"",                    "default:glass",       ""},
			{"default:steel_ingot", "group:wood",          "default:steel_ingot"},
			{"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
		}
	})
	minetest.register_craft({
		output = "motorboat:boat",
		recipe = {
			{"",                  ""},
			{"motorboat:hull", "motorboat:engine"},
		}
	})
end


