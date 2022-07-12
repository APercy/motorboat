--
-- constants
--
local LONGIT_DRAG_FACTOR = 0.13*0.13
local LATER_DRAG_FACTOR = 2.0

motorboat={}
motorboat.gravity = tonumber(minetest.settings:get("movement_gravity")) or 9.8
motorboat.fuel = {['biofuel:biofuel'] = 1,['biofuel:bottle_fuel'] = 1,
                ['biofuel:phial_fuel'] = 0.25, ['biofuel:fuel_can'] = 10}

motorboat.colors ={
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
dofile(minetest.get_modpath("motorboat") .. DIR_DELIM .. "motorboat_custom_physics.lua")


--
-- helpers and co.
--

function motorboat.get_hipotenuse_value(point1, point2)
    return math.sqrt((point1.x - point2.x) ^ 2 + (point1.y - point2.y) ^ 2 + (point1.z - point2.z) ^ 2)
end

function motorboat.dot(v1,v2)
	return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z
end

function motorboat.sign(n)
	return n>=0 and 1 or -1
end

function motorboat.minmax(v,m)
	return math.min(math.abs(v),m)*motorboat.sign(v)
end

function motorboat.setText(self)
    local properties = self.object:get_properties()
    if properties then
        properties.infotext = "Nice motorboat of " .. self.owner
        self.object:set_properties(properties)
    end
end

--returns 0 for old, 1 for new
function motorboat.detect_player_api(player)
    local player_proterties = player:get_properties()
    local mesh = "character.b3d"
    if player_proterties.mesh == mesh then
        local models = player_api.registered_models
        local character = models[mesh]
        if character then
            if character.animations.sit.eye_height then
                return 1
            else
                return 0
            end
        end
    end

    return 0
end

function motorboat.engine_set_sound_and_animation(self)
    --minetest.chat_send_all('test1 ' .. dump(self._engine_running) )
    if self._engine_running then
        if self._last_applied_power ~= self._power_lever then
            --minetest.chat_send_all('test2')
            self._last_applied_power = self._power_lever
            motorboat.engineSoundPlay(self)
        end
    else
        if self.sound_handle then
            minetest.sound_stop(self.sound_handle)
            self.sound_handle = nil
        end
    end
end

function motorboat.engineSoundPlay(self)
    --sound
    if self.sound_handle then minetest.sound_stop(self.sound_handle) end
    if self.object then
        self.sound_handle = minetest.sound_play({name = "motorboat_engine"},
            {object = self.object, gain = 1.0,
                pitch = 0.5 + ((self._power_lever/100)/2),
                max_hear_distance = 32,
                loop = true,})
    end
end

-- attach player
function motorboat.attach(self, player)
    local name = player:get_player_name()
    self.driver_name = name

    -- attach the driver
    player:set_attach(self.pilot_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    local eye_y = -4
    if motorboat.detect_player_api(player) == 1 then
        eye_y = 2.5
    end
    player:set_eye_offset({x = 0, y = eye_y, z = 1}, {x = 0, y = -4, z = -30})
    player_api.player_attached[name] = true
    -- make the driver sit
    minetest.after(0.2, function()
        player = minetest.get_player_by_name(name)
        if player then
	        player_api.set_animation(player, "sit")
        end
    end)
    -- disable gravity
    self.object:set_acceleration(vector.new())
end

-- dettach player
function motorboat.dettach(self, player)
    local name = self.driver_name
    motorboat.setText(self)

    -- driver clicked the object => driver gets off the vehicle
    self.driver_name = nil

    self._engine_running = false
	-- sound and animation
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end
	
	self.engine:set_animation_frame_speed(0)

    -- detach the player
    player:set_detach()
    player_api.player_attached[name] = nil
    player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
    player_api.set_animation(player, "stand")
    self.object:set_acceleration(vector.multiply(motorboat.vector_up, -motorboat.gravity))
end

-- attach passenger
function motorboat.attach_pax(self, player)
    local name = player:get_player_name()
    self._passenger = name
    -- attach the passenger
    player:set_attach(self.passenger_seat_base, "", {x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
    local eye_y = -4
    if motorboat.detect_player_api(player) == 1 then
        eye_y = 2.5
    end
    player:set_eye_offset({x = 0, y = eye_y, z = 1}, {x = 0, y = eye_y, z = -30})
    player_api.player_attached[name] = true
    -- make the driver sit
    minetest.after(0.2, function()
        player = minetest.get_player_by_name(name)
        if player then
            player_api.set_animation(player, "sit")
        end
    end)
end

-- dettach passenger
function motorboat.dettach_pax(self, player)
    local name = self._passenger

    -- passenger clicked the object => driver gets off the vehicle
    self._passenger = nil

    -- detach the player
    if player then
        player:set_detach()
        player_api.player_attached[name] = nil
        player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
        player_api.set_animation(player, "stand")
    end
end

--painting
function motorboat.paint(self, colstr)
    if colstr then
        self.color = colstr
        local l_textures = self.initial_properties.textures
        for _, texture in ipairs(l_textures) do
            local indx = texture:find('motorboat_painting.png')
            if indx then
                l_textures[_] = "motorboat_painting.png^[multiply:".. colstr
            end
        end
	    self.object:set_properties({textures=l_textures})
    end
end

-- destroy the boat
function motorboat.destroy(self, puncher)
    if self.sound_handle then
        minetest.sound_stop(self.sound_handle)
        self.sound_handle = nil
    end

    if self.driver_name then
        -- detach the driver first (puncher must be driver)
        puncher:set_detach()
        puncher:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
        player_api.player_attached[self.driver_name] = nil
        -- player should stand again
        player_api.set_animation(puncher, "stand")
        self.driver_name = nil
    end

    local pos = self.object:get_pos()
    if self.pointer then self.pointer:remove() end
    if self.engine then self.engine:remove() end
    if self.pilot_seat_base then self.pilot_seat_base:remove() end
    if self.passenger_seat_base then self.passenger_seat_base:remove() end

    self.object:remove()

    pos.y=pos.y+2
    for i=1,7 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:steel_ingot')
    end

    for i=1,7 do
	    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:mese_crystal')
    end

    --minetest.add_item({x=pos.x+random()-0.5,y=pos.y,z=pos.z+random()-0.5},'motorboat:boat')
    minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'default:diamond')

    --[[local total_biofuel = math.floor(self._energy) - 1
    for i=0,total_biofuel do
        minetest.add_item({x=pos.x+math.random()-0.5,y=pos.y,z=pos.z+math.random()-0.5},'biofuel:biofuel')
    end]]--
end


--
-- entity
--
minetest.register_entity('motorboat:seat_base',{
initial_properties = {
	physical = false,
	collide_with_objects=false,
	pointable=false,
	visual = "mesh",
	mesh = "seat_base.b3d",
    textures = {"motorboat_black.png",},
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

minetest.register_entity('motorboat:engine',{
initial_properties = {
	physical = false,
	collide_with_objects=false,
	pointable=false,
	visual = "mesh",
	mesh = "engine.b3d",
    --visual_size = {x = 3, y = 3, z = 3},
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
	    mesh = "hull2.b3d",
        textures = {"motorboat_black.png", "motorboat_panel.png", "motorboat_glass.png",
            "motorboat_hull.png", "default_junglewood.png", "motorboat_painting.png"},
    },
    textures = {},
	driver_name = nil,
	sound_handle = nil,
    _energy = 0.001,
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
    _engine_running = false,
    anchored = true,
    _passenger = nil,
    physics = motorboat.physics,
    _auto = false,
    _power_lever = 0,
    _last_applied_power = 0,
    --water_drag = 0,

    get_staticdata = function(self) -- unloaded/unloads ... is now saved
        return minetest.serialize({
            stored_energy = self._energy,
            stored_owner = self.owner,
            stored_hp = self.hp,
            stored_color = self.color,
            stored_anchor = self.anchored,
            stored_driver_name = self.driver_name,
        })
    end,

	on_activate = function(self, staticdata, dtime_s)
        if staticdata ~= "" and staticdata ~= nil then
            local data = minetest.deserialize(staticdata) or {}
            self._energy = data.stored_energy
            self.owner = data.stored_owner
            self.hp = data.stored_hp
            self.color = data.stored_color
            self.anchored = data.stored_anchor
            self.driver_name = data.stored_driver_name
            --minetest.debug("loaded: ", self._energy)
            local properties = self.object:get_properties()
            properties.infotext = data.stored_owner .. " nice motorboat"
            self.object:set_properties(properties)
        end

        motorboat.paint(self, self.color)
        local pos = self.object:get_pos()

	    local engine=minetest.add_entity(pos,'motorboat:engine')
	    engine:set_attach(self.object,'',{x=0,y=6,z=-21},{x=0,y=0,z=0})
		-- set the animation once and later only change the speed
        engine:set_animation({x = 1, y = 8}, 0, 0, true)
	    self.engine = engine

	    local pointer=minetest.add_entity(pos,'motorboat:pointer')
        local energy_indicator_angle = motorboat.get_pointer_angle(self._energy)
	    pointer:set_attach(self.object,'', MOTORBOAT_GAUGE_FUEL_POSITION,{x=0,y=0,z=energy_indicator_angle})
	    self.pointer = pointer

        local pilot_seat_base=minetest.add_entity(pos,'motorboat:seat_base')
        pilot_seat_base:set_attach(self.object,'',{x=-4.2,y=3.8,z=-6},{x=0,y=0,z=0})
	    self.pilot_seat_base = pilot_seat_base

        local passenger_seat_base=minetest.add_entity(pos,'motorboat:seat_base')
        passenger_seat_base:set_attach(self.object,'',{x=4.2,y=3.8,z=-6},{x=0,y=0,z=0})
	    self.passenger_seat_base = passenger_seat_base

		self.object:set_armor_groups({immortal=1})

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

        local hull_direction = minetest.yaw_to_dir(yaw)
        local nhdir = {x=hull_direction.z,y=0,z=-hull_direction.x}		-- lateral unit vector
        local velocity = self.object:get_velocity()
        self.object:set_velocity(velocity)
        local curr_pos = self.object:get_pos()
        self.object:move_to(curr_pos)

        local longit_speed = motorboat.dot(velocity,hull_direction)
        local longit_drag = vector.multiply(hull_direction,longit_speed*longit_speed*
                    LONGIT_DRAG_FACTOR*-1*motorboat.sign(longit_speed))
		local later_speed = motorboat.dot(velocity,nhdir)
		local later_drag = vector.multiply(nhdir,later_speed*later_speed*LATER_DRAG_FACTOR*-1*motorboat.sign(later_speed))
        local accel = vector.add(longit_drag,later_drag)

        local vel = self.object:get_velocity()

        local is_attached = false
        if self.owner then
            local player = minetest.get_player_by_name(self.owner)
            
            if player then
                local player_attach = player:get_attach()
                if player_attach then
                    if player_attach == self.pilot_seat_base then is_attached = true end
                end
            end
        end

		if is_attached then
            local impact = motorboat.get_hipotenuse_value(vel, self.last_vel)
            if impact > 1 then
                --self.damage = self.damage + impact --sum the impact value directly to damage meter
                curr_pos = self.object:get_pos()
                minetest.sound_play("motorboat_collision", {
                    --to_player = self.driver_name,
	                pos = curr_pos,
	                max_hear_distance = 8,
	                gain = 1.0,
                    fade = 0.0,
                    pitch = 1.0,
                })
                --[[if self.damage > 100 then --if acumulated damage is greater than 100, adieu
                    motorboat.destroy(self, puncher)
                end]]--
            end

            --control
			accel = motorboat.motorboat_control(self, dtime, hull_direction,
                longit_speed, longit_drag, later_speed, later_drag, accel) or vel
        else
            -- for some engine error the player can be detached from the submarine, so lets set him attached again
            local can_stop = true
            if self.owner and self.driver_name then
                -- attach the driver again
                local player = minetest.get_player_by_name(self.owner)
                if player then
                    motorboat.attach(self, player)
                    can_stop = false
                end
            end

            if can_stop then
                --detach player
                if self.sound_handle ~= nil then
	                minetest.sound_stop(self.sound_handle)
	                self.sound_handle = nil
                end
            end
		end

        self.engine:set_attach(self.object,'',{x=0,y=6,z=-21},{x=0,y=self.rudder_angle,z=0})

		if math.abs(self.rudder_angle)>5 then
            local turn_rate = math.rad(24)
			newyaw = yaw + self.dtime*(1 - 1 / (math.abs(longit_speed) + 1)) *
                self.rudder_angle / 30 * turn_rate * motorboat.sign(longit_speed)
		end

        -- calculate energy consumption --
        ----------------------------------
        if self._energy > 0 and self._engine_running then
            local zero_reference = vector.new()
            local acceleration = motorboat.get_hipotenuse_value(accel, zero_reference)
            local consumed_power = acceleration/6000
            self._energy = self._energy - consumed_power;

            local energy_indicator_angle = motorboat.get_pointer_angle(self._energy)
            if self.pointer:get_luaentity() then
                self.pointer:set_attach(self.object,'',MOTORBOAT_GAUGE_FUEL_POSITION,{x=0,y=0,z=energy_indicator_angle})
            else
                --in case it have lost the entity by some conflict
                self.pointer=minetest.add_entity({x=0,y=5.52451,z=5.89734},'motorboat:pointer')
                self.pointer:set_attach(self.object,'',MOTORBOAT_GAUGE_FUEL_POSITION,{x=0,y=0,z=energy_indicator_angle})
            end
        end
        if self._energy <= 0 and self._engine_running then
            self._engine_running = false
            if self.sound_handle then minetest.sound_stop(self.sound_handle) end
		    self.engine:set_animation_frame_speed(0)
        end
        ----------------------------
        -- end energy consumption --

        --roll adjust
        ---------------------------------
		local sdir = minetest.yaw_to_dir(newyaw)
		local snormal = {x=sdir.z,y=0,z=-sdir.x}	-- rightside, dot is negative
		local prsr = motorboat.dot(snormal,nhdir)
        local rollfactor = -10
        local newroll = (prsr*math.rad(rollfactor))*later_speed
        --minetest.chat_send_all('newroll: '.. newroll)
        ---------------------------------
        -- end roll

		local bob = motorboat.minmax(motorboat.dot(accel,hull_direction),0.8)	-- vertical bobbing

		if self.isinliquid then
            if self._last_rnd == nil then self._last_rnd = math.random(1, 3) end
            if self._last_water_touch == nil then self._last_water_touch = self._last_rnd end
            if self._last_water_touch <= self._last_rnd then
                self._last_water_touch = self._last_water_touch + self.dtime
            end
            if math.abs(bob) > 0.1 and self._last_water_touch >=self._last_rnd then
                self._last_rnd = math.random(1, 3)
                self._last_water_touch = 0
                minetest.sound_play("default_water_footstep", {
                    --to_player = self.driver_name,
                    object = self.object,
                    max_hear_distance = 15,
                    gain = 0.07,
                    fade = 0.0,
                    pitch = 1.0,
                }, true)
            end

			accel.y = accel_y + bob
			newpitch = velocity.y * math.rad(6)

            motorboat.engine_set_sound_and_animation(self)

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
        local is_admin = false
        is_admin = minetest.check_player_privs(puncher, {server=true})
		local name = puncher:get_player_name()
        if self.owner and self.owner ~= name and self.owner ~= "" then
            if is_admin == false then return end
        end
        if self.owner == nil then
            self.owner = name
        end
        	
        if self.driver_name and self.driver_name ~= name then
			-- do not allow other players to remove the object while there is a driver
			return
		end
        
        local is_attached = false
        if puncher:get_attach() == self.pilot_seat_base then is_attached = true end

        local itmstck=puncher:get_wielded_item()
        local item_name = ""
        if itmstck then item_name = itmstck:get_name() end

        if is_attached == true and self._engine_running == false then
            --minetest.chat_send_all('refuel')
            --refuel
            motorboat.loadFuel(self, puncher:get_player_name())
        end

        if is_attached == false then

            -- deal with painting or destroying
		    if itmstck then
			    local _,indx = item_name:find('dye:')
			    if indx then

                    --lets paint!!!!
				    local color = item_name:sub(indx+1)
				    local colstr = motorboat.colors[color]
                    --minetest.chat_send_all(color ..' '.. dump(colstr))
				    if colstr then
                        motorboat.paint(self, colstr)
					    itmstck:set_count(itmstck:get_count()-1)
					    puncher:set_wielded_item(itmstck)
				    end
                    -- end painting

			    else -- deal damage
				    if not self.driver and toolcaps and toolcaps.damage_groups and toolcaps.damage_groups.fleshy then
					    --mobkit.hurt(self,toolcaps.damage_groups.fleshy - 1)
					    --mobkit.make_sound(self,'hit')
                        self.hp = self.hp - 10
                        minetest.sound_play("motorboat_collision", {
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
                motorboat.destroy(self, puncher)
            end

        end
        
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end

		local name = clicker:get_player_name()

        if self.owner == "" then
            self.owner = name
        end

        if self.owner == name then
		    if name == self.driver_name then
			    -- driver clicked the object => driver gets off the vehicle
                motorboat.dettach(self, clicker)
                if self._passenger then
                    local passenger = minetest.get_player_by_name(self._passenger)
                    if passenger then
                        motorboat.dettach_pax(self, passenger)
                    end
                end
		    elseif not self.driver_name then
                -- temporary------
                self.hp = 50 -- why? cause I can desist from destroy
                ------------------

                motorboat.attach(self, clicker)
		    end
        else
            --passenger section
            --only can enter when the pilot is inside
            if self.driver_name then
                if self._passenger == nil then
                    motorboat.attach_pax(self, clicker)
                else
                    motorboat.dettach_pax(self, clicker)
                end
            else
                if self._passenger then
                    motorboat.dettach_pax(self, clicker)
                end
            end
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

                local properties = ent.object:get_properties()
                properties.infotext = owner .. " nice motorboat"
                ent.object:set_properties(properties)
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


-- add chatcommand to eject from motorboat

minetest.register_chatcommand("motorboat_eject", {
	params = "",
	description = "Ejects from motorboat",
	privs = {interact = true},
	func = function(name, param)
        local colorstring = core.colorize('#ff0000', " >>> you are not inside your motorboat")
        local player = minetest.get_player_by_name(name)
        local attached_to = player:get_attach()

		if attached_to ~= nil then
            local parent = attached_to:get_attach()
            if parent ~= nil then
                local entity = parent:get_luaentity()
                if entity.driver_name == name and entity.name == "motorboat:boat" then
                    motorboat.dettach(entity, player)
                else
			        minetest.chat_send_player(name,colorstring)
                end
            end
		else
			minetest.chat_send_player(name,colorstring)
		end
	end
})
