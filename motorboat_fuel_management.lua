--
-- fuel
--
MOTORBOAT_GAUGE_FUEL_POSITION = {x=0,y=5.52451,z=2.3}

minetest.register_entity('motorboat:pointer',{
initial_properties = {
	physical = false,
	collide_with_objects=false,
	pointable=false,
	visual = "mesh",
	mesh = "pointer.b3d",
	textures = {"clay.png"},
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

function motorboat.get_gauge_angle(value, initial_angle)
    initial_angle = initial_angle or 90
    local angle = value * 18
    angle = angle - initial_angle
    angle = angle * -1
	return angle
end

function motorboat.contains(table, val)
    for k,v in pairs(table) do
        if k == val then
            return v
        end
    end
    return false
end

function motorboat.loadFuel(self, player_name)
    local player = minetest.get_player_by_name(player_name)
    local inv = player:get_inventory()

    local itmstck=player:get_wielded_item()
    local item_name = ""
    if itmstck then item_name = itmstck:get_name() end

    local fuel = motorboat.contains(motorboat.fuel, item_name)
    if fuel then
        local stack = ItemStack(item_name .. " 1")

        if self._energy < 10 then
            inv:remove_item("main", stack)
            self._energy = self._energy + fuel
            if self._energy > 10 then self._energy = 10 end

            local energy_indicator_angle = motorboat.get_gauge_angle(self._energy)
            self.pointer:set_attach(self.object,'',MOTORBOAT_GAUGE_FUEL_POSITION,{x=0,y=0,z=energy_indicator_angle})
        end
        
        return true
    end

    return false
end
