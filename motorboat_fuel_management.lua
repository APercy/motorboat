--
-- fuel
--
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

function motorboat_load_fuel(self, player_name)
    if self.energy < 9.5 then 
        local player = minetest.get_player_by_name(player_name)
        local inv = player:get_inventory()
        local inventory_fuel = "biofuel:biofuel"

        if inv:contains_item("main", inventory_fuel) then
            local stack = ItemStack(inventory_fuel .. " 1")
            local taken = inv:remove_item("main", stack)

	        self.energy = self.energy + 1
            if self.energy > 10 then self.energy = 10 end

            local energy_indicator_angle = motorboat.get_pointer_angle(self.energy)
            self.pointer:set_attach(self.object,'',{x=0,y=5.52451,z=5.89734},{x=0,y=0,z=energy_indicator_angle})
	    end
    else
        print("Full tank.")
    end
end

