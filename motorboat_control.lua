--global constants

motorboat.motorboat_last_time_command = 0
motorboat.vector_up = vector.new(0, 1, 0)

function motorboat.get_pointer_angle(energy)
    local angle = energy * 18
    angle = angle - 90
    angle = angle * -1
	return angle
end

function motorboat.check_node_below(obj)
	local pos_below = obj:get_pos()
	pos_below.y = pos_below.y - 0.1
	local node_below = minetest.get_node(pos_below).name
	local nodedef = minetest.registered_nodes[node_below]
	local touching_ground = not nodedef or -- unknown nodes are solid
			nodedef.walkable or false
	local liquid_below = not touching_ground and nodedef.liquidtype ~= "none"
	return touching_ground, liquid_below
end

function motorboat.motorboat_control(self, dtime, hull_direction, longit_speed,
        longit_drag, later_speed, later_drag, accel)
    motorboat.motorboat_last_time_command = motorboat.motorboat_last_time_command + dtime
    if motorboat.motorboat_last_time_command > 1 then motorboat.motorboat_last_time_command = 1 end
	local player = minetest.get_player_by_name(self.driver_name)
    local retval_accel = accel;
    
	-- player control
	if player then
        --minetest.chat_send_all('teste')
		local ctrl = player:get_player_control()
        local max_speed_anchor = 0.2
        if ctrl.sneak and motorboat.motorboat_last_time_command > 0.3 and
                longit_speed < max_speed_anchor and longit_speed > -max_speed_anchor then
            motorboat.motorboat_last_time_command = 0
		    if self.anchored == false then
                self.anchored = true
                self.object:set_velocity(vector.new())
                minetest.chat_send_player(self.driver_name, 'anchors away!')
            else
                self.anchored = false
                minetest.chat_send_player(self.driver_name, 'weigh anchor!')
            end
        end

        if ctrl.jump and self._engine_running and motorboat.motorboat_last_time_command > 0.3 then
            motorboat.motorboat_last_time_command = 0
            minetest.chat_send_player(self.driver_name, 'running in auto mode')
            self._auto = true
        end

		if ctrl.sneak then
            if longit_speed >= max_speed_anchor or longit_speed <= -max_speed_anchor then
                self.rudder_angle = 0
            end
		end

        if self.anchored == false then
            if self._engine_running then
                local engineacc
                if self._auto == false then
		            if longit_speed < 8.0 and ctrl.up then
			            engineacc = 1.5
		            else
                        if longit_speed > -1 and ctrl.down then
			                engineacc = -0.1
                        end
		            end
                else
                    --auto mode
                    if longit_speed < 8.0 then engineacc = 1.5 end
                    if ctrl.down or ctrl.up then
                        minetest.chat_send_player(self.driver_name, 'auto turned off')
                        self._auto = false
                    end
                end

		        if engineacc then retval_accel=vector.add(accel,vector.multiply(hull_direction,engineacc)) end
                --minetest.chat_send_all('paddle: '.. paddleacc)
            else
		        local paddleacc
		        if longit_speed < 1.0 and ctrl.up then
			        paddleacc = 0.5
		        elseif longit_speed >  -1.0 and ctrl.down then
			        paddleacc = -0.5
		        end
		        if paddleacc then retval_accel=vector.add(accel,vector.multiply(hull_direction,paddleacc)) end
                --minetest.chat_send_all('paddle: '.. paddleacc)
            end
        end

		if ctrl.aux1 then
            self._auto = false
            --sets the engine running - but sets a delay also, cause keypress
            if motorboat.motorboat_last_time_command > 0.3 then
                motorboat.motorboat_last_time_command = 0
			    if self._engine_running then
				    self._engine_running = false
			        -- sound and animation
                    if self.sound_handle then
                        minetest.sound_stop(self.sound_handle)
                        self.sound_handle = nil
                    end
			        self.engine:set_animation_frame_speed(0)

			    elseif self._engine_running == false and self._energy > 0 then
				    self._engine_running = true
		            -- sound and animation
	                self.sound_handle = minetest.sound_play({name = "engine"},
			                {object = self.object, gain = 2.0, max_hear_distance = 32, loop = true,})
                    self.engine:set_animation_frame_speed(30)
			    end
            end
		end

		-- rudder
        local rudder_limit = 30
		if ctrl.right then
			self.rudder_angle = math.max(self.rudder_angle-20*dtime,-rudder_limit)
		elseif ctrl.left then
			self.rudder_angle = math.min(self.rudder_angle+20*dtime,rudder_limit)
		end
	end
    return retval_accel
end


