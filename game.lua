-- title:  game title
-- author: LAZK
-- desc:   short description
-- script: lua

-- constants

local DRAW_FLAG = 0
local SOLID_FLAG = 1
local OPAQUE_FLAG = 2
local FLOOR_BLOCK = 3
local HALF_BLOCK = 4
local FULL_BLOCK = 5
local ANIMATED_FLAG = 6

local PALETTE_ADDR=0x03FC0

-- sound effects

function sfx_slide_whistle()
	sfx(16,"F-6",128,3,15,4)
end

function sfx_footstep()
	sfx(17,"F-4",16,3,15,4)
end

function sfx_magic()
	sfx(18,"G#3",128,3,15,4)
end

function sfx_enemy_hit()
	sfx(19,"C-5",56,3,15,4)
end

function sfx_demon_girl_voice()
	sfx(20,"C-5",-1,3,15,4)
end

function sfx_slime_girl_voice()
	sfx(21,"G#5",-1,3,15,4)
end

function sfx_skeleton()
	sfx(22,"D#5",27*4,3,15,4)
end

function sfx_player_hit()
	sfx(23,"G#4",21*4,3,15,4)
end

local s_t,s_end=-1,-1

function sfx_stop_after(t)
	s_t=0
	s_end=t
end

function sfx_stop()
	sfx(-1,0,-1,3,15,0)
	s_t=-1
	s_end=-1
end

function sfx_tick()
	if s_t<0 or s_end<0 then return end
	s_t=s_t+1
	if s_t>=s_end then
		sfx_stop()
	end
end

-- path tracing

function path_inc(x0,y0,x1,y1)
	if x1<x0 or y1<y0 then
		return {}
	end
	local ix,iy=x0,y0
	local points={{ix,iy}}
	local mdx,mdy=math.abs(x1-x0),math.abs(y1-y0)

	while ix~=x1 or iy~=y1 do
		local dx,dy=math.abs(x1-ix)/mdx,math.abs(y1-iy)/mdy

		if dy<dx and ix<x1 then
			ix=ix+1
		elseif dx<dy and iy<y1 then
			iy=iy+1
		elseif ix<x1 then
			ix=ix+1
		else
			iy=iy+1
		end

		table.insert(points,{ix,iy})
	end
	return points
end

function path(x0,y0,x1,y1)
	local points
	if x0<=x1 and y0<=y1 then
		points=path_inc(x0,y0,x1,y1)
	elseif x0<=x1 and y1<=y0 then
		points=path_inc(x0,y0,x1,y0+(y0-y1))
		for k,v in pairs(points) do
			v[2]=y0-(v[2]-y0)
		end
	elseif x1<=x0 and y0<=y1 then
		points=path_inc(x0,y0,x0+(x0-x1),y1)
		for k,v in pairs(points) do
			v[1]=x0-(v[1]-x0)
		end
	elseif x1<=x0 and y1<=y0 then
		points=path_inc(x0,y0,x0+(x0-x1),y0+(y0-y1))
		for k,v in pairs(points) do
			v[1]=x0-(v[1]-x0)
			v[2]=y0-(v[2]-y0)
		end
	end
	return points
end

-- map generation

local enemy_palettes={
	default=nil
}

local room_palettes={
	default={full_wall=3,half_wall=5,floor={1,1,1,96},door=52,decor={32,64,50},enemy_frequency=0.02,enemies=enemy_palettes.default,extra={}},
	mossy_room={full_wall=3,half_wall=5,floor={98,100,102,104},door=52,decor={},enemy_frequency=0,enemies={},extra={}},
	shop_room={full_wall=11,half_wall=7,floor={1,1,1,96},door=52,decor={},enemy_frequency=0,enemies={},extra={}}
}

local dungeon_palettes={
	default={
		{prob=10,e=room_palettes.default},
		{prob=2,e=room_palettes.mossy_room}
	}
}

function get_random_from_palette(palette)
	local max = 0
	for k,v in pairs(palette) do
		max=max+v.prob
	end

	local rand=math.random(1,max)
	local i=1
	while rand>palette[i].prob do
		rand=rand-palette[i].prob
		i=i+1
	end

	return palette[i].e
end

function set_tile(map,x,y,val)
	if not map[x] then map[x]={} end
	if type(val)=="table" then val=val[math.random(1,#val)] end
	map[x][y]=val
end

function square_room(map,palette,x0,y0,x1,y1,doors)
	for x=x0,x1 do
		for y=y0,y1 do
			if x==x0 or y==y0 then
				set_tile(map,x,y,palette.full_wall)
			elseif x==x1 or y==y1 then
				set_tile(map,x,y,palette.half_wall)
			else
				local floor=palette.floor
				if type(floor)=="table" then
					floor=floor[math.random(1,#floor)]
				end
				set_tile(map,x,y,floor)
			end
		end
	end

	for i=1,math.random(1,((x1-x0)*(y1-y0))//10+1) do
		if #palette.decor==0 then break end
		local x,y
		local decor=palette.decor[math.random(1,#palette.decor)]
		if fget(decor,SOLID_FLAG) then
			x=math.random(x0+2,x1-2)
			y=math.random(y0+2,y1-2)
		else
			x=math.random(x0+1,x1-1)
			y=math.random(y0+1,y1-1)
		end
		set_tile(map,x,y,decor)
	end

	for k,v in pairs(doors) do
		set_tile(map,x0+v[1],y0+v[2],palette.floor)
		create_door(x0+v[1],y0+v[2],x0+v[1]==x0 or x0+v[1]==x1)
	end

	if palette.enemy_frequency>0 then
		for i=1,math.random(math.ceil((x1-x0)*(y1-y0)*palette.enemy_frequency))*2 do
			local x=math.random(x0+2,x1-2)
			local y=math.random(y0+2,y1-2)
			while fget(iso_mget(x,y,map),SOLID_FLAG) do
				x=math.random(x0+2,x1-2)
				y=math.random(y0+2,y1-2)
			end
			local enemy = get_random_from_palette(palette.enemies)
			enemy(x,y)
		end
	end
	return map
end

local shop_layout={
	{"floor","floor","floor","floor","floor","floor","floor"},
	{"fwall","floor","floor","slime","floor","floor","fwall"},
	{"floor","pedes","floor","pedes","floor","pedes","floor"},
	{"floor","floor","floor","floor","floor","floor","floor"},
}

function shop_register(map,palette,x0,y0)
	for x=1,7 do
		for y=1,4 do
			if shop_layout[y][x] == "floor" then
				set_tile(map,x0+x,y0+y,palette.floor)
			elseif shop_layout[y][x] == "fwall" then
				set_tile(map,x0+x,y0+y,palette.full_wall)
			elseif shop_layout[y][x] == "pedes" then
				set_tile(map,x0+x,y0+y,palette.floor)
				create_random_pedestal(x0+x,y0+y)
			elseif shop_layout[y][x] == "slime" then
				set_tile(map,x0+x,y0+y,palette.floor)
				slime_girl(x0+x,y0+y)
			end
		end
	end
end

function shop_room(map,palette,x0,y0,x1,y1,doors)
	square_room(map,palette,x0,y0,x1,y1,doors)

	shop_register(map,palette,x0+2,y0+2)

	return map
end

function straight_corridor(map,palette,x0,y0,dir,dist)
	if dir=="u" then
		for y=y0,y0-dist,-1 do
			set_tile(map,x0-1,y,palette.full_wall)
			set_tile(map,x0,y,palette.floor)
			set_tile(map,x0+1,y,palette.full_wall)
		end
	elseif dir=="r" then
		for x=x0,x0+dist do
			set_tile(map,x,y0-1,palette.full_wall)
			set_tile(map,x,y0,palette.floor)
			set_tile(map,x,y0+1,palette.half_wall)
		end
	elseif dir=="d" then
		for y=y0,y0+dist do
			set_tile(map,x0-1,y,palette.full_wall)
			set_tile(map,x0,y,palette.floor)
			set_tile(map,x0+1,y,palette.full_wall)
		end
	elseif dir=="l" then
		for x=x0,x0-dist,-1 do
			set_tile(map,x,y0-1,palette.full_wall)
			set_tile(map,x,y0,palette.floor)
			set_tile(map,x,y0+1,palette.half_wall)
		end
	end
end

function split(x0,y0,x1,y1)
	if x1-x0<5 or y1-y0<5 then return {{x0,y0,x1,y1}} end
	local dir
	if x1-x0>(y1-y0) then
		dir=1
	elseif y1-y0>(x1-x0) then
		dir=2
	end
	dir=dir or math.random(1,2)
	local rooms={}
	if dir==1 then
		local split_line=math.random(x0+5,x1-5)
		rooms[1]={x0,y0,split_line,y1}
		rooms[2]={split_line,y0,x1,y1}
	else
		local split_line=math.random(y0+5,y1-5)
		rooms[1]={x0,y0,x1,split_line}
		rooms[2]={x0,split_line,x1,y1}
	end
	return {rooms[1],rooms[2]}
end

function init_dungeon(x,y,w,h)
	return {{x=x,y=y,w=w,h=h,conn={}}}
end

function lines_overlap(x0,w0,x1,w1)
	return (x0<=x1+w1 and x0>=x1) or (x1<=x0+w0 and x1>=x0)
end

function can_connect(room1,room2)
	return lines_overlap(room1.x+1,room1.w-1,room2.x+1,room2.w-1) or lines_overlap(room1.y+1,room1.h-1,room2.y+1,room2.h-1)
end

function connect_rooms(room1,room2)
	if room1.x>room2.x+room2.w then -- room1 right of room2
		local miny,maxy
		if room1.y<room2.y then miny=room2.y+1 else miny=room1.y+1 end
		if room1.y+room1.h<room2.y+room2.h then maxy=room1.y+room1.h-1 else maxy=room2.y+room2.h-1 end
		local y=math.random(miny,maxy)
		room1.conn[room2]={0,y-room1.y}
		room2.conn[room1]={room2.w,y-room2.y}
	elseif room1.y>room2.y+room2.h then -- room1 down of room2
		local minx,maxx
		if room1.x<room2.x then minx=room2.x+1 else minx=room1.x+1 end
		if room1.x+room1.w<room2.x+room2.w then maxx=room1.x+room1.w-1 else maxx=room2.x+room2.w-1 end
		local x=math.random(minx,maxx)
		room1.conn[room2]={x-room1.x,0}
		room2.conn[room1]={x-room2.x,room2.h}
	elseif room2.x>room1.x+room1.w then -- room1 left of room2
		local miny,maxy
		if room1.y<room2.y then miny=room2.y+1 else miny=room1.y+1 end
		if room1.y+room1.h<room2.y+room2.h then maxy=room1.y+room1.h-1 else maxy=room2.y+room2.h-1 end
		local y=math.random(miny,maxy)
		room1.conn[room2]={room1.w,y-room1.y}
		room2.conn[room1]={0,y-room2.y}
	else -- room1 up of room2
		local minx,maxx
		if room1.x<room2.x then minx=room2.x+1 else minx=room1.x+1 end
		if room1.x+room1.w<room2.x+room2.w then maxx=room1.x+room1.w-1 else maxx=room2.x+room2.w-1 end
		local x=math.random(minx,maxx)
		room1.conn[room2]={x-room1.x,room1.h}
		room2.conn[room1]={x-room2.x,0}
	end
end

function disconnect(room1,room2)
	room1.conn[room2]=nil
	room2.conn[room1]=nil
end

function split_once(dungeon,minw,minh,spacing)
	local room=dungeon[math.random(1,#dungeon)]
	local d=room.h-room.w
	local timeout=0
	while (room.w<minw*2+4+spacing+1 and d<=0) or (room.h<minh*2+4+spacing+1 and d>=0) do
		if timeout>20 then return end
		room=dungeon[math.random(1,#dungeon)]
		d=room.h-room.w
		timeout=timeout+1
	end

	if d>0 then
		local split_y=math.random(0,room.h-(minh*2+4+spacing))+spacing+2+minh
		local prev_h=room.h
		room.h=split_y-spacing
		local new_room={x=room.x,y=room.y+room.h+spacing,w=room.w,h=prev_h-room.h-spacing,conn={}}
		table.insert(dungeon,new_room)
		for c_room,conn in pairs(room.conn) do
			if c_room.y>room.y+room.h then
				disconnect(c_room,room)
				connect_rooms(c_room,new_room)
			end
		end
		connect_rooms(room,new_room)
	else
		local split_x=math.random(0,room.w-(minw*2+4+spacing))+spacing+2+minw
		local prev_w=room.w
		room.w=split_x-spacing
		local new_room={x=room.x+room.w+spacing,y=room.y,w=prev_w-room.w-spacing,h=room.h,conn={}}
		table.insert(dungeon,new_room)
		for c_room,conn in pairs(room.conn) do
			if c_room.x>room.x+room.w then
				disconnect(c_room,room)
				connect_rooms(c_room,new_room)
			end
		end
		connect_rooms(room,new_room)
	end
	for other,coord in pairs(room.conn) do
		if can_connect(room,other) then
			connect_rooms(room,other)
		else
			disconnect(room,other)
		end
	end
end

function dungeon_generator(xmax,ymax,spacing,dungeon_palette)
	local rooms=init_dungeon(0,0,xmax,ymax)
	spacing=spacing or 3
	local shop_generated=false
	dungeon_palette=dungeon_palette or dungeon_palettes.default
	for i=1,math.random((xmax*ymax)//20-5,(xmax*ymax)//20+5) do
		split_once(rooms,5,5,spacing)
	end

	local map={}

	for i=#rooms,1,-1 do
		local room=rooms[i]
		local palette=get_random_from_palette(dungeon_palette)

		if room.w>=9 and room.h>=6 and not shop_generated then
			shop_room(map,room_palettes.shop_room,room.x,room.y,room.x+room.w,room.y+room.h,room.conn)
			shop_generated=true
		else
			square_room(map,palette,room.x,room.y,room.x+room.w,room.y+room.h,room.conn)
		end
		for k,conn in pairs(room.conn) do
			local palette=get_random_from_palette(dungeon_palette)
			local dir
			if conn[1]==0 then dir="l"
			elseif conn[1]==room.w then dir="r"
			elseif conn[2]==0 then dir="u"
			else dir="d"
			end
			straight_corridor(map,room_palettes.default,room.x+conn[1],room.y+conn[2],dir,spacing//2)
		end
	end

	return map
end

local sample_map
-- custom drawing

function init_node(e)
	return {l=nil,r=nil,e=e}
end

function insert(t,e)
	if e.z<t.e.z then
		if not t.l then
			t.l=init_node(e)
		else
			insert(t.l,e)
		end
	else
		if not t.r then
			t.r=init_node(e)
		else
			insert(t.r,e)
		end
	end
end

function tree_list(t)
	function inner(t,a)
		if not t then
			return a
		end
		inner(t.l,a)
		table.insert(a,t.e)
		inner(t.r,a)
		return a
	end
	return inner(t,{})
end

local drawing_tree=nil

function start_draw()
 drawing_tree=init_node({id=nil,z=136/2})
end

function final_draw()
	for k,e in pairs(tree_list(drawing_tree)) do
		if e.id then
			spr(e.id,e.x,e.y,e.colorkey,e.scale,e.flip,e.rotate,e.w,e.h)
		end
	end
end

function pre_spr(id,x,y,colorkey,scale,flip,rotate,w,h,z)
	local e={
		id=id,x=x,y=y,
		colorkey=colorkey or -1,
		scale=scale or 1,
		flip=flip or 0,
		rotate=rotate or 0,
		w=w or 1,
		h=h or 1,
		z=y+(z or 0)
	}
	insert(drawing_tree,e)
end

-- iso helpers

function calc_iso(x,y)
	local xx=8*x
	local xy=5*x
	local yx=-8*y
	local yy=5*y 
	return xx+yx,xy+yy
end

-- map drawing

local animations={
	[225]={frames={{t=45,s=225},{t=45,s=227}}}
}

local a_ticks=0

function tick()
	a_ticks=a_ticks+1
end

function animate(sprite)
	if not animations[sprite] then return sprite end
	if not animations[sprite].max then
		local max = 0
		for k,v in pairs(animations[sprite].frames) do
			max=max+v.t
		end
		animations[sprite].max=max
	end
	local counter=a_ticks%animations[sprite].max
	local index=1
	while counter>animations[sprite].frames[index].t do
		counter=counter-animations[sprite].frames[index].t
		index=index+1
	end
	return animations[sprite].frames[index].s
end

function map_iso(x,y,w,h,sx,sy)
	for ix=x,x+w do
		for iy=y,y+h do
			local sprite=iso_mget(ix,iy)
			if fget(sprite,DRAW_FLAG) then
				if is_visible(ix,iy) then
					if fget(sprite, ANIMATED_FLAG) then
						sprite=animate(sprite)
					end
					local colorkey=0
					if sprite>=9 and sprite<=11 then colorkey=8 end
					if sprite==7 then colorkey=5 end
					local dx,dy=calc_iso(ix,iy)
					if fget(sprite,FLOOR_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,colorkey,1,0,0,2,2)
					elseif fget(sprite,HALF_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,colorkey,1,0,0,2,2)
					elseif fget(sprite,FULL_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,colorkey,1,0,0,2,3)
					end
					if is_visible(ix,iy) == "was visible" then
						if fget(sprite,FLOOR_BLOCK) then
							spr_iso(400,dx+sx,dy+sy,0,1,0,0,2,2)
						elseif fget(sprite,HALF_BLOCK) then
							spr_iso(402,dx+sx,dy+sy,0,1,0,0,2,2,1)
						elseif fget(sprite,FULL_BLOCK) then
							spr_iso(388,dx+sx,dy+sy,0,1,0,0,2,3,1) 
						end
					end
				end
			end
		end
	end
end

function iso_mget(x,y,map)
	map=map or sample_map
	if not map[x] or 
	   not map[x][y] then
		return 0
	else
		return map[x][y]
	end
end

-- camera

local camera={
	x=0,y=0,w=220,h=136
}

function update_camera(c,p)
	local px,py=calc_iso(p.x,p.y)	
	
	c.x=px-c.w/2
	c.y=py-c.h/2
end

function spr_iso(index,x,y,colorkey,scale,flip,rotate,w,h,z)	
	if h>2 then
		y=y-(h-2)*8
		local nz = z or 0
		z=nz+(h-2)*8
	end
	pre_spr(index,x-camera.x,y-camera.y,colorkey,scale,flip,rotate,w,h,z)
end

--- game logic

-- turn handling
local turn_id=1

local turn_order={
	"player",
	"enemy"
}

function turn()
	return turn_order[turn_id]
end

function next_turn()
	turn_id=(turn_id%#turn_order) + 1
end

function turn_is_inactive()
	local match=true
	function check(o)
		if o.turn==turn() then match=false end
	end
	map_objects(check)
	return match
end

function take_turns()
	while turn_is_inactive() do
		next_turn()
	end
	local turn_taken = false
	function take_turn(o)
		if o.turn=="player" then
			turn_taken=turn_taken or o:do_turn()
		end
	end
	map_objects(take_turn)
	if turn_taken then 
		enemy_do_turns()
	end
end

function player_turn(p)
	if turn()~="player" then
		return
	end
	local did_move=false
	if p:do_turn() then
		did_move=true
	end
	
	if did_move then
		next_turn()
	end
end

function enemy_turn()
	if turn()~="enemy" then
		return
	end
	enemy_do_turns()
	next_turn()
end

-- visibility

local visible={}
local was_visible={}

function set_visible(x,y)
	if not visible[x] then visible[x]={} end	
	visible[x][y]=true
end

function is_visible(x,y)
	if visible[x] and visible[x][y] then
		return "visible"
	elseif was_visible[x] and was_visible[x][y] then 
		return "was visible"
	end
	return nil
end

function clear_visible()
	for x,xs in pairs(visible) do
		if not was_visible[x] then was_visible[x]={} end
		for y,ys in pairs(xs) do
			was_visible[x][y]=ys			
		end
	end
	
	visible={}
end

function dumb_visibility()
	for x=player.x-2,player.x+2 do
		for y=player.y-2,player.y+2 do
			set_visible(x,y)
		end
	end
end

function plot_line_low(x0,y0,x1,y1)
	local arr={}
	local dx=x1-x0
	local dy=y1-y0
	local yi=1
	if dy<0 then
		yi=-1
		dy=-dy
	end
	local D=2*dy-dx
	local y=y0
	for x=x0,x1 do
		table.insert(arr,{x,y})
		if D>0 then
			y=y+yi
			D=D-2*dx
		end
		D=D+2*dy
	end
	return arr
end

function plot_line_high(x0,y0,x1,y1)
	local arr={}
	local dx=x1-x0
	local dy=y1-y0
	local xi=1
	if dx<0 then
		xi=-1
		dx=-dx
	end
	local D=2*dx-dy
	local x=x0
	for y=y0,y1 do
		table.insert(arr,{x,y})
		if D>0 then
			x=x+xi
			D=D-2*dy
		end
		D=D+2*dx
	end
	return arr
end

function plot_line(x0,y0,x1,y1)
	if math.abs(y1-y0)<math.abs(x1-x0) then
		if x0>x1 then
			return plot_line_low(x1,y1,x0,y0)
		else
			return plot_line_low(x0,y0,x1,y1)
		end
	else
		if y0>y1 then
			return plot_line_high(x1,y1,x0,y0)
		else
			return plot_line_high(x0,y0,x1,y1)
			end
	end
end

function can_see(x0,y0,x1,y1)
	local arr=plot_line(x0,y0,x1,y1)	
	for k,v in pairs(arr) do
		if (fget(iso_mget(v[1],v[2]),OPAQUE_FLAG) and not (x1==v[1] and y1==v[2])) or not fget(iso_mget(v[1],v[2]), DRAW_FLAG) then
			return false
		end
	end
	return true
end

function shadow_casting(p,range)
	for x=p.x-range,p.x+range do
		for y=p.y-range,p.y+range do
			if can_see(p.x,p.y,x,y) then
				set_visible(x,y)
			end
		end
	end
end

--- objects

Object = {
	mt={},
	prototype={
		turn=nil
	}
}

function Object.new(init)
	setmetatable(init,Object.mt)
	init:register()
	return init
end

function Object.prototype:hit()
end

function Object.mt.__index(t,k)
	return Object.prototype[k]
end

local object_map={}

function Object.prototype:register()
	if not object_map[self.x] then object_map[self.x] = {} end
	object_map[self.x][self.y]=self
end

function Object.prototype:remove()
	object_map[self.x][self.y] = nil
end

function Object.prototype:move(x,y)
	if peek_obj(x,y) then return object_map[x][y] end
	self:remove()
	self.x=x
	self.y=y
	self:register()
	if self.did_move then self:did_move() end
	return false
end

function peek_obj(x,y)
	return object_map[x] and object_map[x][y]
end

function map_objects(f)
	local objs = {}
	for k,row in pairs(object_map) do
		for k,o in pairs(row) do
			table.insert(objs,o)
		end
	end
	for k,o in pairs(objs) do
		f(o)
	end
end

function draw_objects()
	function draw(o)
		o:draw()
	end
	map_objects(draw)
end

function is_solid(x,y,map)
	return fget(iso_mget(x,y,map),SOLID_FLAG)
end

-- player code

local player=Object.new({
	x=2,y=2,
	sprite_front=474,sprite_back=426,
	facing=0,
	turn="player",
	player=true,
	hp=4,max_hp=4,alive=true,
	money=0,
	animation={
		tick=0,max=80,
		frames={{i=0,t=40},{i=1,t=10},{i=2,t=10},{i=0,t=10},{i=3,t=10}}
	},
	items={
		health_pots=0,
		weapon_up=false,
	}
})

function player:get_frame()
	local tick=self.animation.tick%self.animation.max
	local i=1

	while tick>self.animation.frames[i].t do
		tick=tick-self.animation.frames[i].t
		i=i+1
	end

	return self.animation.frames[i].i
end

function player:do_turn()
	local did_move=false
	local obj = nil

	if btnp(0,20,5) and not is_solid(self.x,self.y-1) then
		obj=self:move(self.x,self.y-1)
		self.facing=4
		did_move=true
	elseif btnp(1,20,5) and not is_solid(self.x,self.y+1) then
		obj=self:move(self.x,self.y+1)
		self.facing=1
		did_move=true
	elseif btnp(2,20,5) and not is_solid(self.x-1,self.y) then
		obj=self:move(self.x-1,self.y)
		self.facing=3
		did_move=true
	elseif btnp(3,20,5) and not is_solid(self.x+1,self.y) then
		obj=self:move(self.x+1,self.y)
		self.facing=0
		did_move=true
	end

	if obj and obj.hit then
		self:attack(obj)
	end

	if btnp(7) then
		did_move=true
	end

	if not did_move and btnp(5) and self.items.health_pots > 0 then
		self.items.health_pots=self.items.health_pots - 1
		self.hp=self.hp+2
		if self.hp>self.max_hp then self.hp=self.max_hp end
	end

	return did_move
end

function player:draw()
	self.animation.tick=self.animation.tick+1
	local ix,iy=calc_iso(self.x,self.y)
	if self.facing<=2 then
		spr_iso(self.sprite_front+self:get_frame(),
			ix+4,iy,
			0,1,self.facing,0,1,3,1)
	elseif self.facing>=3 then
		spr_iso(self.sprite_back+self:get_frame(),
			ix+4,iy,
			0,1,self.facing-3,0,1,3,1)
	end
end

function player:hud(x,y)
	for i=1,self.items.health_pots do
		spr(253,x+(i-1)*9,y,0)
	end
	if self.items.weapon_up then
		spr(261,x,y+9,0)
	end
end

function player:attack(obj)
	local dmg = 1
	if self.items.weapon_up then dmg=2 end
	local res = obj:hit(dmg,self)
	if res then self.money=self.money+res end
end

function player:hit(dmg)
	sfx_player_hit()
	self.hp=self.hp-dmg
	if self.hp<1 then
		self:die()
	end
end

function player:die()
	sfx_slide_whistle()
	self:remove()
	self.alive=false
end

function player:did_move()
	sfx_footstep()
end


function player:add_item(item)
	if item=="health" then
		self.items.health_pots = self.items.health_pots+1
	elseif item=="weapon" then
		self.items.weapon_up = true
	end
end

-- enemy code

function create_enemy(x,y,sprite,hp,atk,value)
	local enemy = Object.new({
		x=x,y=y,sprite=sprite,
		enemy=true,hp=hp,atk=atk or 1,
		turn="enemy",state="wander",value=value
	})

	local dirs={
		{0,1},{1,0},{0,-1},{-1,0}
	}

	function enemy:draw()
		if is_visible(self.x,self.y)~="visible" then return end
		local ix,iy=calc_iso(self.x,self.y)
		spr_iso(self.sprite,ix,iy,0,1,0,0,2,3,1)
	end

	function enemy:do_turn()
		if player.alive and can_see(self.x,self.y,player.x,player.y) then self.state="charge" else self.state="wander" end
		if self.state=="wander" then
			return self:wander()
		end
		if self.state=="charge" then
			return self:charge()
		end
	end

	function enemy:try_move(x,y)
		if not is_solid(x,y) then
			local obj=self:move(x,y)
			if obj and not obj.enemy then obj:hit(self.atk) end
			return true
		end
		return false
	end

	function enemy:wander()
		local dir=dirs[math.random(1,#dirs)]
		self:try_move(self.x+dir[1],self.y+dir[1])
		return true
	end

	function enemy:charge()
		local path = path(self.x,self.y,player.x,player.y)
		local move=self:try_move(path[2][1],path[2][2])
		if not move then self:wander() end
		return true
	end

	function enemy:die()
		sfx_skeleton()
		self:remove()
		return self.value
	end

	function enemy:hit(dmg)
		sfx_enemy_hit()
		self.hp=self.hp-dmg
		if self.hp<1 then
			return self:die()
		end
		return 0
	end

	return enemy
end

function enemy_do_turns()
	function do_turn(o)
		if o.enemy then o:do_turn() end
	end
	map_objects(do_turn)
end

function rave_skeleton(x,y)
	local enemy=create_enemy(x,y,464,1,1,5)
end

function link_the_skeleton(x,y)
	local enemy=create_enemy(x,y,466,2,1,10)
end

function turtleneck_skeleton(x,y)
	local enemy=create_enemy(x,y,468,1,2,10)
end

-- door

function create_door(x,y,flip)
	local door = Object.new({
		x=x,y=y,sprite=52,
	})

	if flip then door.flip=1 else door.flip=0 end

	function door:hit()
		self:remove()
	end

	function door:draw()
		if not is_visible(self.x,self.y) then return end
		local ix,iy=calc_iso(self.x,self.y)
		spr_iso(self.sprite,ix,iy,0,1,door.flip,0,2,3,1)
	end

	return door
end

--- ui
-- ui elements


-- ui logic

function show_resource_bar(s,x,y,res,max_res)
	for i=0,max_res-1,1 do
		local dx=res-i
		spr(s,x+i*18,y,8,1,0,0,2,2)
		if dx>=1 then
			spr(s+2,x+i*18,y,0,1,0,0,2,2)
		elseif dx==1 then
			spr(s+2,x+i*18,y,0,1,0,0,2,1)
		end
	end
end

function show_money(s,x,y,amount)
	spr(s,x,y,0)
	font("x"..tostring(amount),x+9,y)
end


function wrap(str, limit, indent, indent1)
	indent = indent or ""
	indent1 = indent1 or indent
	limit = limit or 72
	local here = 1-#indent1
	local function check(sp, st, word, fi)
	   if fi - here > limit then
		  here = st - #indent
		  return "\n"..indent..word
	   end
	end
	return indent1..str:gsub("(%s+)()(%S+)()", check)
end

SIDE_LEFT=0
SIDE_RIGHT=1

Dialogue={
	mt={},
	pt={margin=5,text_margin=2,rows=4,sprite=2}
}

function Dialogue.mt.__index(t,k)
	return Dialogue.pt[k]
end

function Dialogue.new(head,side,text,sound)
	local dialogue=setmetatable({head=head,side=side,index=1,sound=sound},Dialogue.mt)
	dialogue:chunk_text(text)
	return dialogue
end

function Dialogue.pt:text_height()
	return self.rows*9+self.text_margin*2-1
end

function Dialogue.pt:text_space()
	local x,y,w,h=self:dimensions()
	local sx,sy,sw,sh=self:sprite_dimensions()
	return w-sw
end

function Dialogue.pt:text_start(row)
	local x,y,w,h=self:dimensions()
	local sx,sy,sw,sh=self:sprite_dimensions()
	if self.side==SIDE_LEFT then
		return sx+sw,y+self.text_margin+9*(row-1)
	elseif self.side==SIDE_RIGHT then
		return x+self.text_margin,y+self.text_margin+9*(row-1)
	else
		return 0,0
	end
end

function Dialogue.pt:dimensions()
	return self.margin,136-self.margin-self:text_height(),220-self.margin*2,self:text_height()
end

function Dialogue.pt:sprite_dimensions()
	local x,y,w,h=self:dimensions()
	if self.side==SIDE_LEFT then
		x=x
	elseif self.side==SIDE_RIGHT then
		x=x+w-(self.sprite*8*2+self.text_margin*2)
	end
	return x,y,self.sprite*8*2+self.text_margin*2,self.sprite*8*2+self.text_margin*2
end

function Dialogue.pt:chunk_text(text)
	local word_map={}
	for word in string.gmatch(text,"%g+") do
		table.insert(word_map,{word,font(word,0,-8,0)})
	end
	local lines,line,line_len={},"",0
	for k,v in pairs(word_map) do
		if line_len==0 or (line_len+v[2]<self:text_space()) then
			line=line..v[1].." "
			line_len=line_len+v[2]+8
		else
			table.insert(lines,{line,line_len})
			line,line_len=v[1].." ",v[2]+8
		end
	end
	if line~="" then table.insert(lines,{line,line_len}) end
	self.lines=lines
end

function Dialogue.pt:draw()
	local x,y,w,h=self:dimensions()
	local sx,sy,sw,sh=self:sprite_dimensions()
	rect(x,y,w,h,0)
	rectb(x,y,w,h,12)
	spr(self.head,sx+self.text_margin,sy+self.text_margin,0,self.sprite,self.side,0,2,2)
	for i=1,self.rows do
		local row = (self.index-1)*self.rows+i
		if not self.lines[row] then break end
		local line = self.lines[row]
		local tx,ty=self:text_start((row-1)%self.rows+1)
		font(line[1],tx+(7+self:text_space()-line[2])*self.side,ty,0)
	end
end

function Dialogue.pt:next()
	self.index=self.index+1
	if (self.index-1)*self.rows + 1 > #self.lines then
		return true
	end
	self.sound()
	sfx_stop_after(60)
	return false
end

function Dialogue.pt:is_complete()
	return not self.lines[(self.index-1)*self.rows+1]
end

function Dialogue.pt:reset()
	self.index=1
end

Choice={
	mt={},
	pt=setmetatable({rows=3,selection_sprite=248,super=Dialogue.pt},Dialogue.mt)
}

function Choice.mt.__index(t,k) return Choice.pt[k] end

function Choice.new(head,side,text,sound,accept_callback,deny_callback)
	local choice = setmetatable({
		text=text,accept_callback=accept_callback,deny_callback=deny_callback,
		confirm_length=font("yes",0,-8),deny_length=font("no",0,-8),confirm=true,
		complete=false,
		head=head,side=side,sound=sound,
	},Choice.mt)
	return choice
end

function Choice.pt:draw()
	local x,y,w,h=self:dimensions()
	local sx,sy,sw,sh=self:sprite_dimensions()

	rect(x,y,w,h,0)
	rectb(x,y,w,h,12)
	spr(self.head,sx+self.text_margin,sy+self.text_margin,0,self.sprite,self.side,0,2,2)
	
	local tx,ty=self:text_start(1)
	font(self.text,tx+sw*self.side,ty,0)

	local rel=self:text_space()/5
	local tx,ty=self:text_start(3)
	self:draw_choice("yes",tx+rel,ty,self.confirm)
	self:draw_choice("no",tx+rel*4-self.deny_length,ty,not self.confirm)
end

function Choice.pt:draw_choice(text,x,y,selected)
	local len=font(text,x+9,y)
	if selected then
		spr(self.selection_sprite,x,y)
		spr(self.selection_sprite,x+len+10,y,0,1,1)
	end
end

function Choice.pt:text_height()
	return self.super.text_height(self)+9
end

function Choice.pt:next()
	if self.confirm then
		self.accept_callback()
	else
		self.deny_callback()
	end
	return true
end

function Choice.pt:swap()
	self.confirm=not self.confirm
end

function Choice.pt:dimensions()
	return self.margin,136-self.margin-self:text_height(),220-self.margin*2,self:text_height()
end

function Choice.pt:is_complete()
	return self.complete
end

function Choice.pt:reset()

end

Conversation={
	mt={},
	pt={}
}

function Conversation.mt.__index(t,k) return Conversation.pt[k] end

function Conversation.new()
	return setmetatable({dialogues={},current_dialogue=1},Conversation.mt)
end

function Conversation.pt:is_complete()
	return self.current_dialogue > #self.dialogues
end

function Conversation.pt:add_dialogue(dialogue)
	table.insert(self.dialogues,dialogue)
end

function Conversation.pt:get_dialogue()
	return self.dialogues[self.current_dialogue]
end

function Conversation.pt:draw()
	if not self:is_complete() then
		self:get_dialogue():draw()
	end
end

function Conversation.pt:next()
	if self:get_dialogue():next() then
		self.current_dialogue=self.current_dialogue+1
		if self:get_dialogue() then 
			self:get_dialogue().sound()
			sfx_stop_after(60)
		end
	end
end

function Conversation.pt:swap()
	if self:get_dialogue() and self:get_dialogue().swap then
		self:get_dialogue():swap()
	end
end

function Conversation.pt:copy()
	local copy=Conversation.new()
	for k,v in pairs(self.dialogues) do
		copy.add_dialogue(v)
	end
	return copy
end

function Conversation.pt:reset()
	self.current_dialogue=1
	for k,v in pairs(self.dialogues) do
		v:reset()
	end
end

-- conversations

local DEMON_GIRL_HEAD=256
local SLIME_GIRL_HEAD=258

local intro_conversation=Conversation.new()
intro_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"This is my third dungeon today. Asmodeus, I can't wait to get home and spend some time with my gf.",sfx_demon_girl_voice))

local slime_girl_conversation=Conversation.new()
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Hello and welcome to CrypTrip. How may I help you?",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"What?",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,".. Hm?",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Oh, hello my Damned Angel! \\",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Sorry, long day, really tired.",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"What are you doing here Jelly?",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Just selling my soul to the highest bidder.",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Haha, yeah.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"But seriously.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You remember the job I was talking about?",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Sure.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Well here I am, want some stuff?",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Uh, I guess? What do you have?",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"We have red drinks! And this nifty weapon!",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Pretty crap selection.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Yeah, you'd imagine such a popular tourist destination would have a better selection.",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Yep, the popular tourist destination of deep down in a random crypt.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Hey, crypt delving has become a more popular pastime as of late!",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Yeah, I know. It's making it harder for us professional crypt delvers to be taken seriously.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Just because you earn money doing it doesn't make you better than them you know.",sfx_slime_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"You know what I mean, dork.",sfx_demon_girl_voice))
slime_girl_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"I do, Heathen. \\",sfx_slime_girl_voice))

local hp_1_conversation=Conversation.new()
hp_1_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Oh you want a red drink? Why's that?",sfx_slime_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"It's a health potion, right?",sfx_demon_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"No, it's a red drink. I have no idea as to what it's gonna do to you.",sfx_slime_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"...",sfx_demon_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"It could be juice for all I know, maybe wine. Why do you think I'd know what's in that?",sfx_slime_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Well you are selling it so I'd imagine you'd have some idea of what is in it.",sfx_demon_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Listen, I just work here.",sfx_slime_girl_voice))
hp_1_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Well alrighty then.",sfx_demon_girl_voice))

local hp_1_conversation_yes_success=Conversation.new()
hp_1_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Okay, I'll take the health potion.",sfx_demon_girl_voice))
hp_1_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You mean the red drink, right?",sfx_slime_girl_voice))
hp_1_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Yeah, yeah sure. I'll take the \"Red Drink\"",sfx_demon_girl_voice))
hp_1_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Okay! Thank you for shopping at CrypTrip!",sfx_slime_girl_voice))

local hp_1_conversation_yes_fail=Conversation.new()
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"As long as i'm living with you it'll be fine \\.",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Okay, I'll take the health potion.",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You mean red drink, right? That'll be #= coin.",sfx_slime_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Wait I have to pay!?",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Well yeah, this is a store.",sfx_slime_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"But I'm your girlfriend!",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Love doesn't pay the bills.",sfx_slime_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"WE PAY THE SAME BILLS!",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Yeah but my boss pays me and he'll only get money if I sell stuff so I don't get paid unless he gets paid which means you gotta pay.",sfx_slime_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Hmph.",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"So... That'll be 30 coin.",sfx_slime_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I don't have enough. Sorry, Jelly",sfx_demon_girl_voice))
hp_1_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"It's okay. Hope you're fine with living in debt!",sfx_slime_girl_voice))

local hp_1_conversation_no=Conversation.new()
hp_1_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I think I'll pass. There could be anything in there as far as I know!",sfx_demon_girl_voice))
hp_1_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"True! Better safe than sorry!",sfx_slime_girl_voice))

local hp_2_conversation=Conversation.new()
hp_2_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Woah calm down there, you sure you can handle my strongest potions?",sfx_slime_girl_voice))
hp_2_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Haha. Very funny, potion seller.",sfx_demon_girl_voice))

local hp_2_conversation_yes_success=Conversation.new()
hp_2_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"One red drink coming up!",sfx_slime_girl_voice))
hp_2_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Why would they be selling red drinks to adventurers if it's not a health potion?",sfx_demon_girl_voice))
hp_2_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"I dunno, maybe it makes you into a horse person or something.",sfx_slime_girl_voice))
hp_2_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Wouldn't be the first time.",sfx_demon_girl_voice))

local hp_2_conversation_yes_fail=Conversation.new()
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"My potions are too strong for you, traveller.",sfx_slime_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Jelly come on, I need a potion.",sfx_demon_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"My strongest potions would kill you, traveler. You can't handle my strongest potions. You'd better go to a seller that sells weaker potions.",sfx_slime_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Listen! I just need a single potion!",sfx_demon_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You can't handle my strongest potions! No one can! My strongest potions aren't fit for a beast let alone a girl!",sfx_slime_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"...Please?",sfx_demon_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You uh… don't have enough coin.",sfx_slime_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"You could have just said that!",sfx_demon_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Well it's a lot less fun to say \"you're too broke\".",sfx_slime_girl_voice))
hp_2_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Heh, fair enough.",sfx_demon_girl_voice))

local hp_2_conversation_no=Conversation.new()
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I'm just looking anyway.",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Why look at the potions when you can look at me. \\",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I'm at work, Jelly.",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Me too! I get a bonus if I can distract the enemy!",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I'm your enemy?",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"According to my contract, yeah.",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"But that's only when I'm on the clock!",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Ah.",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Wait, why are you selling me stuff if I'm your enemy?",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Oh, the boss gets a bonus if he can sell a lot of stuff, doesn't matter who buys it.",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I think my job is to kill that guy.",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Oh! ",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Maybe you shouldn't buy my stuff then?",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Isn't that gonna cut into your paycheck or something?",sfx_demon_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Eh, if you kill him that won't matter anyway.",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Good luck my Damned Angel. \\",sfx_slime_girl_voice))
hp_2_conversation_no:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Thanks, jelly.",sfx_demon_girl_voice))

local wu_conversation=Conversation.new()
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Oh! You hadn't told me you liked maces!",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Maces?",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Yes, that's what i call flails.",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"You call flails \"maces\"?",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Yes, it's a regional dialect.",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"What region?",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Hell.",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Really? Well I'm from the Second Level of Hell and I've never heard anyone call flails \"maces\".",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Wait, really? I thought you were from The Abyss?",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"No, Jelly, I'm just going along with the joke.",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"What, oh! Right, from The Shimshons!",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Yes- Wait you weren't making that joke?",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Nope, pure coincidence!",sfx_slime_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Uh huh.",sfx_demon_girl_voice))
wu_conversation:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Anyway want this mace?",sfx_slime_girl_voice))

local wu_conversation_yes_success=Conversation.new()
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Woah, wait a minute... Where did you get all this money from?",sfx_slime_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Those skeletons were attacking me and dropped it when they died.",sfx_demon_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"You killed my co-workers?",sfx_slime_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Oh, crap sorry-",sfx_demon_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Haha, just kidding, they'll be back. Undead y'know.",sfx_slime_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Here, have the flail. It's on the house.",sfx_slime_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I paid for it.",sfx_demon_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Yeah, you paid to get it for free!",sfx_slime_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"...",sfx_demon_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"I love you.",sfx_demon_girl_voice))
wu_conversation_yes_success:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"I love you too. \\",sfx_slime_girl_voice))

local wu_conversation_yes_fail=Conversation.new()
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Sure, whatever you say Jelly.",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Great! That'll be 90!",sfx_slime_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Oh, Mammon! That's a lot!",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Duh, it's a mace.",sfx_slime_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Flail, but yeah i don't have that much.",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Mace. That's fine, you heretic, come back when you have more!",sfx_slime_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Flail.",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"Mace.",sfx_slime_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Flail.",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(SLIME_GIRL_HEAD,SIDE_RIGHT,"*kiss*",sfx_slime_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"*kiss*",sfx_demon_girl_voice))
wu_conversation_yes_fail:add_dialogue(Dialogue.new(DEMON_GIRL_HEAD,SIDE_LEFT,"Ok, I'll be back Jelly. \\",sfx_demon_girl_voice))

local wu_conversation_no=Conversation.new()

-- main menu

local new_game_len=font("new game",0,-8)

function draw_title(x,y)
	spr(167,x-(9/2)*8,y,0,1,0,0,9,4)
	spr(232,x-(9/2)*8+8,y+4*8,0,1,0,0,7,1)
end

function draw_new_game(x,y)
	font("new game", x-new_game_len/2,y,0)
	if (a_ticks//18)%2==0 then return end
	spr(248,x-new_game_len/2-10,y)
	spr(248,x+new_game_len/2+2,y,0,1,1)
end

-- shop

function create_pedestal(x,y,sprite,item_sprite,item_name,price,f,head,conversation,ys,yf,n)
	local pedestal = Object.new({
		x=x,y=y,sprite=sprite,item_sprite=item_sprite,f=f,bought=false
	})

	conversation:add_dialogue(Choice.new(head or 0,SIDE_RIGHT,"Buy "..item_name.." for \n"..price.."g?",sfx_slime_girl_voice,function()
		if price>player.money then
			start_conversation(yf)
			return
		end
		start_conversation(ys)
		player.money=player.money-price
		f()
		pedestal.bought=true
	end,function()
		start_conversation(n)
	end))

	function pedestal:hit(dmg,p)
		if not p or not p.player then return end
		if not self.bought then
			if conversation:is_complete() then conversation:reset() end
			start_conversation(conversation)
		end
	end

	function pedestal:draw()
		if not is_visible(self.x,self.y) then return end
		local ix,iy=calc_iso(self.x,self.y)
		spr_iso(self.sprite,ix,iy,5,1,0,0,2,2,2)
		if not self.bought then
			spr_iso(self.item_sprite,ix+4,iy-2,0,1,0,0,1,1,8)
		end

	end

	return pedestal
end

local shop_items = {
	{
		sprite=385,
		name="health potion",
		price=30,
		f=function() player.items.health_pots=player.items.health_pots+1 end,
		conversation=hp_1_conversation,
		yes_success=hp_1_conversation_yes_success,
		yes_fail=hp_1_conversation_yes_fail,
		no=hp_1_conversation_no,
		limit=1,
	},
	{
		sprite=385,
		name="health potion",
		price=30,
		f=function() player.items.health_pots=player.items.health_pots+1 end,
		conversation=hp_2_conversation,
		yes_success=hp_2_conversation_yes_success,
		yes_fail=hp_2_conversation_yes_fail,
		no=hp_2_conversation_no,
		limit=1,
	},
	{
		sprite=390,
		name="weapon",
		price=90,
		f=function() player.items.weapon_up=true end,
		conversation=wu_conversation,
		yes_success=wu_conversation_yes_success,
		yes_fail=wu_conversation_yes_fail,
		no=wu_conversation_no,
		limit=1,
	}
}

function create_random_pedestal(x,y)
	local item = shop_items[math.random(1,#shop_items)]
	while item.limit==0 do
		item = shop_items[math.random(1,#shop_items)]
	end
	item.limit=item.limit-1
	return create_pedestal(x,y,7,item.sprite,item.name,item.price,item.f,258,item.conversation,item.yes_success,item.yes_fail,item.no)
end

-- slime girl

function slime_girl(x,y,conversation)
	local girl=Object.new({
		x=x,y=y,animation={0,1,2,3},base_sprite=470,
		conversation=conversation or Conversation.new()
	})

	function girl:draw()
		if not is_visible(self.x,self.y) then return end
		local ix,iy=calc_iso(self.x,self.y)
		local frame = self.base_sprite + self.animation[(a_ticks//10)%#self.animation + 1]
		spr_iso(frame,ix,iy,0,1,1,0,1,3,3)
	end

	function girl:hit(dmg,p)
		if not p or not p.player then return end
		start_conversation(slime_girl_conversation)
	end

	return girl
end

-- main

enemy_palettes.default={{prob=9,e=rave_skeleton},{prob=3,e=link_the_skeleton},{prob=3,e=turtleneck_skeleton}}
room_palettes.default.enemies=enemy_palettes.default

local playing_music=false
sample_map = dungeon_generator(40,40,6)
local state = "mainmenu"
local state_stack = {}
local states



function swap_state(new_state,...)
	table.insert(state_stack,{state,{...}})
	state=new_state
end

function pop_state()
	local popped_state=table.remove(state_stack)
	state=popped_state[1]
	if state=="conversation" then
		states[state].conversation=popped_state[2][1]
	end
end

function peek_state()
	return state_stack[#state_stack][1]
end

states={
	game={
		update=function() 
			clear_visible()
			take_turns()
			shadow_casting(player,6)
		end,
		draw=function()
			cls()
			update_camera(camera,player)
			local dx,dy=player.x,player.y
			if dx-8<0 then dx=0 else dx=dx-8 end
			if dy-8<0 then dy=0 else dy=dy-8 end
			map_iso(dx,dy,16,16,0,0)
			draw_objects()
		end,
		hud=function()
			show_resource_bar(432,1,1,player.hp,player.max_hp)
			show_money(384,1,18,player.money)
			player:hud(0,32)
		end,
		music=function()
			if not playing_music then
				music(0,0,0,true,true)
				playing_music=true
			end
		end,
	},
	conversation={
		update=function()
			if not states[state].conversation then pop_state() end
			if btnp(4) then
				states[state].conversation:next()
			end
			if btnp(2) or btnp(3) then
				states[state].conversation:swap()
			end
			if states[state].conversation:is_complete() then
				pop_state()
			end
		end,
		draw=function()
		end,
		hud=function()
			if not states[state].conversation then return end
			states[state].conversation:draw()
		end,
		music=function() end,
		conversation=nil
	},
	mainmenu={
		update=function()
			if btnp(4) then 
				swap_state("game")
				start_conversation(intro_conversation)
			end
		end,
		draw=function()
			cls()
			draw_title(220//2,32)
			draw_new_game(220//2,80)
		end,
		hud=function() end,
		music=function() end,
	}
}

function start_conversation(conversation)
	if conversation:is_complete() then conversation:reset() end
	swap_state("conversation",conversation)
	states[state].conversation=conversation
end

function OVR()
	states[state].hud()
end

function TIC()
	states[state].update()
	states[state].music()
	start_draw()
	states[state].draw()
	final_draw()
	sfx_tick()
	tick()
end

-- <TILES>
-- 001:000000000000000000000000000000000000000000000000000000000000000e
-- 002:00000000000000000000000000000000000000000000000000000000e0000000
-- 003:0000000f00000ffe000ffeef0ffeffeefeefeeeedddeeeeededddeeeddededde
-- 004:f0000000fff00000efeff000eeeeeff0eeeefeffeeeeeddfeeeddeefeddedeef
-- 005:0000000f00000fff000fffee0fffefeefefeeeeedddeeeeeddeddeeededdedde
-- 006:f0000000eff00000fefff000eeefeff0eeeeeeffeeeeeddfeeeddeffeddeefef
-- 007:555555505555500955500998500998887a988888777998887de77998777ff779
-- 008:05555555900555558990055588899005888889a78889977789977ff7977ed777
-- 009:888888888888888888888888888888888888888888888888888888888888888f
-- 010:88888888888888888888888888888888888888888888888888888888f8888888
-- 011:888888878888877d88877ffe877fffff7ffe7fff777defff7de77ff7777ff77e
-- 012:78888888e77888887ff77888fffed778fff7eff7fffff777eff77ff7d77ed777
-- 016:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 017:00000eef000eeff70eeff77f7ffeefff077ffeef00077ffe0000077f00000007
-- 018:fee000007ffee000f77ffee0fff77ffefeeff770eff77000f770000070000000
-- 019:ddeedeefdeeeeeefddeeeeefdeeeeeefdeeeeeffdeeeeeefddeeeeffddeeeeff
-- 020:ddedeeefddeeeeefdeeeeeffddeeeeffdeeeeeefddeeeeefddeeefefdeeeeeff
-- 021:ddeeeeefddeeeeefdeeeeeffdeeefeff0fffefef000ffeff00000fff0000000f
-- 022:ddedeeefddeeefefdedeeeffddeefeffdeefeff0dfeff000dff00000d0000000
-- 023:77e77de70ed717770771f7e70e077ed7500f077755500e705555500055555550
-- 024:7ff77177777e7f10717de7707f1770f07770e00507f005550005555505555555
-- 025:88888ff1888ff7fd8ff77f77011de777800f7f708880007e8888800188888880
-- 026:1ff88888e77ff88877777ff8707ed11f77007008d77008881008888808888888
-- 027:77e77de77ed717707771f7e07e777ed0777f777001777e70777e777707777177
-- 028:7ff77177777e7f17717de7777f1777f77777e77777f777e07777177707e77770
-- 032:000000000000000000000000000000000000000000000000000000000000000e
-- 033:00000000000000000000000000000000000000000000000000000000e0000000
-- 034:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 035:ddeeeeffdeeeeeefddeeefefdeefeeff0ffeffef000ffeff00000fff0000000f
-- 036:deeeeeefddeeeeffdeeeefffdeeeeeffdeefeff0defff000dff00000d0000000
-- 043:07e770770ed710770771f0e00e007ed0800f000088800e708888800088888880
-- 044:07077170070e7f10717de7707f1770f07770e00807f008880008888808888888
-- 048:00000ee3000ee3320ee332237f32233307733223000773320000077300000007
-- 049:3ee00000233ee00032233ee0333223fe32233770233770003770000070000000
-- 050:0000000f00000ffe000ffeff0ffeefeefeefeeeedddeeeeeddeddeeededeedde
-- 051:f0000000fff00000efeff000eefefff0eedeefefeeededdfdeeddeefeddedeff
-- 052:0000000000000000000000000000660000066666000666660006566600065655
-- 053:0000000000000000000000000000000000000000660000006666000066660000
-- 054:0000000000000000000000000000330000033333000777330007ff770007efff
-- 055:0000000000000000000000000000000000000000330000003333000077730000
-- 056:0000000000000000000000000000880000088888000777880007ff770007efff
-- 057:0000000000000000000000000000000000000000880000008888000077780000
-- 064:000000000000000000000000000000000000000000000000000000000000000e
-- 065:00000000000000000000000000000000000000000000000000000000e0000000
-- 066:dffefeff0ddfffef0feddfff00ffeddd00dffeed00de8ffd00de99ef0feddaef
-- 067:ddefeff0ddeffdd0dffdded0fddeef00fedfff00fff9ef00de8aed00de9dded0
-- 068:00065555000656550006565500065655000656c400065c560006546600066644
-- 069:6566000065660000556600006566000065660000456600004666000065660000
-- 070:0007ffff0007ffff0007efff0007ffff0007fccc0007fc220007f4230007e433
-- 071:ff730000fe730000ff730000ff7300004e7300004f7300004f7300004f730000
-- 072:0007ffff0007ffff0007efff0007ffff0007fccc0007fc880007f4890007e499
-- 073:ff780000fe780000ff780000ff7800004e7800004f7800004f7800004f780000
-- 080:00000ee9000ee9980ee998897f98899907799889000779980000077900000007
-- 081:9ee00000899ee00098899ee0999889fe98899770899770009770000070000000
-- 082:dffeeddfdddffedddedddffdddededdd0ffeeeef000ffeff00000fff0000000f
-- 083:dddeeffffefffddffffddefffddeefefdeefeff0dedff000dff00000d0000000
-- 084:0006665500065655000666650006566500006656000000660000000000000000
-- 085:6666000066660000656600006666000065660000656600006666000000660000
-- 086:0007ff440007ffff0007efff0007ffff000077ff000000770000000000000000
-- 087:ff730000fe730000ff730000ff730000fe7300007f7300007773000000730000
-- 088:0007ff440007ffff0007efff0007ffff000077ff000000770000000000000000
-- 089:ff780000fe780000ff780000ff780000fe7800007f7800007778000000780000
-- 096:0000000000000000000000000000000000000000000000000000000000000007
-- 097:0000000000000000000000000000000000000000000000000000000070000000
-- 098:000000000000000000000000000000000000000000000000000000000000000e
-- 099:00000000000000000000000000000000000000000000000000000000e0000000
-- 100:000000000000000000000000000000000000000000000000000000000000000e
-- 101:00000000000000000000000000000000000000000000000000000000e0000000
-- 102:000000000000000000000000000000000000000000000000000000000000000a
-- 103:00000000000000000000000000000000000000000000000000000000a0000000
-- 104:000000000000000000000000000000000000000000000000000000000000000a
-- 105:00000000000000000000000000000000000000000000000000000000a0000000
-- 112:0000077f00077ffe077ffeefeff77fff0eeff77f000eeff700000eef0000000e
-- 113:f7700000eff77000feeff770fffeeff7f77ffee07ffee000fee00000e0000000
-- 114:00000eef000eeff70e8ff77f98feefff088ffeef00089fae00000aaf0000000a
-- 115:fee000007ffee000f77ffee0fff77ffefeeff770eff77000f770000090000000
-- 116:00000eef000eeff70eeff77f7ffeefff077ffeef00077ffe0000077f0000000a
-- 117:fee000007ffee000f77ffee0fff77ff8fee9fa809ffaa000f9a0000090000000
-- 118:00000a9f000aaff9088f877f9ff8efff077ffeef00077ffe0000077f00000007
-- 119:fee000007ffee000f77ffee0fff77ffefeeff770eff77000f770000070000000
-- 120:00000eea000eeff70eeff77f7ffeefff077ffeef00077ffe0000077f00000007
-- 121:f9a000007afa8000f778f890fff77ff9feeff7a0eff77000f770000070000000
-- 128:000000000000000000000000000000000000000000000000000000000000000e
-- 129:0000000000000000000000000000000000000000000000000000000060000000
-- 144:00000ed6000ff6650ef66556d665566606566666000666650000065600000006
-- 145:6560000056666000666665606665566e65566ed0566ff0006ef00000d0000000
-- 167:000000d00000000000000ddd00000d0000000d0d00000d0000000dee00000000
-- 168:d0edd0ee0000000dddddeedd0d0000000e000ddd0e00ddd00e0ddd000e00de00
-- 169:00000000000000000000000000000000dd00dddd00e00dd00000ddd0de000de0
-- 170:00000000000000000000000000000000dd0000d000d00d00e00e0d00d00e00dd
-- 171:000000000000000000000000000000000dddd0dd00dd000d00dd00dddddee00d
-- 172:00000000000000000000000000000000ddde000dd000d00dd0e00e0de0d00e0d
-- 173:00000000000000000000000000000000dddddee000dd00e00ddee0e000de00e0
-- 174:000dd0ed000d0000000eeddd00000000000000000ddddd00ddeeeed0d00e00e0
-- 175:d0e0d00000000000deedde000e000e000e0d0d000d000d000d0edd000d000000
-- 183:00000d0e000000000000e0dd00000000000e0dee000000000000e0ed00000000
-- 184:ee00de000e0dee00ee00eed00e000eedde0000000e0ddddddd00dd000d0dddde
-- 185:ee000de00000deee00e00ee0ed00eede00000000d000dddd0e000dd000e00dd0
-- 186:00e00000ed0000dd0d0d0d0000de00de00000000ddee0ddd000e00ddd0000ddd
-- 187:00de000d00de00de0ded000eeee000ee00000000dde000dd0000000dd00000dd
-- 188:e000d000eeed0000d0000000ede0000000000000dd0edd0dd000e000d000e000
-- 189:00de00000deed00000ee0000eeeddd0000000000dddddee0dd0000e0dd0d0000
-- 190:e00e00e0e0dee0e00deeee000d0e0e0000000000ddddde000dd000e0ddd0e00e
-- 191:0ddd0d000d0000000eedd0d00e0000000eeedd0e0e0000000dded0d00e000000
-- 199:00000e0e0000000000000edd00000e0000000e0d00000d0000000ddd00000000
-- 200:ee00dd000e00de000d0deeee0d00ee000e0eeeed0e000000deedeeed0000000d
-- 201:00e0dddd00e00de000d00de00e000ee0d000eeee0000000000d0000d0d0e00d0
-- 202:ee0000dde00000de000000de000e00eedede0eed00000000000d00dee0d0e0dd
-- 203:0000000d0000000d0000d00e0000e00eeedde0ee00000000d0ddd000e0d0000d
-- 204:e00e000de0e00000e0d00000ee000000edee000e00000000d00dd0000e0d0d0d
-- 205:dddee000dd0e0000de000000de0000e0eeeedee000000000d00d0d0d0e0d0e00
-- 206:0de0e00d0de000e0deeeee000ee00d0eeede00de00000000de0deeedd00e0000
-- 207:0eed0d000e0000000d0edd000e000d000d0d0e000d000e00ddedee0000000000
-- 215:000000e000000000000000000000000000000000000000000000000000000000
-- 216:e0eed0ee00000000000000000000000000d000dd0d0e00d00dde00d00d0e00e0
-- 217:0ded00d00d0e00e00e0e000e0000000000ddd0ddd0d000ede0dd00d0e0e000d0
-- 218:00dee0d0d0e0e0e0d0e0e0e000000000d00d00dde0d0d0d0e0d0e0d0e0e0e0e0
-- 219:e0ed000de0d0000ee0eee00d000000000000000dd00000d0e00000dde0dd00d0
-- 220:de0de00d0e0e0e0e0e0de00000000000000dde0dd00d000de00ede0de0000e0e
-- 221:0e0d0e000e0e0e00e000ed0000000000000dde0d0000d00e0000d00d0000e00d
-- 222:d00ee0ede0000000e000000000000000de0edd00de0d00000e0de0000e0e000d
-- 223:d0e0d000000000000000000000000000000000000000000000000000e0000000
-- 224:0000000000000000000000000000000000000000000000000000000000000003
-- 225:0000000000000000000000000000000000000000000000000000000030000000
-- 226:0000000000000000000000000000000000000000000000000000000000000003
-- 227:0000000000000000000000000000000000000000000000000000000030000000
-- 228:000000000000000000000000000000000000000000000000000000000000000b
-- 229:00000000000000000000000000000000000000000000000000000000b0000000
-- 230:000000000000000000000000000000000000000000000000000000000000000b
-- 231:00000000000000000000000000000000000000000000000000000000b0000000
-- 232:0e0e00de000000000000d00d000d0d0d000dde0e000e0e0d000d0e0e00000000
-- 233:00eee0e000000000e00dd0000d0d0e000e0d0d000e0d0e000e0ee00000000000
-- 234:e00e00d0000000000d000d00d0d0d0d0d000ded0e0e0e0e00d00d0e000000000
-- 235:e00e00e000000000dd00ddd0d0d00d00ee000e00d0000d00e000dee000000000
-- 236:e00dee0d00000000ddd00d000d00d0e00e00dde00d00d0e00d00e0e000000000
-- 237:ee0dee0e00000000d000dee0d0000d00e0000d00e0000e00dde0edd000000000
-- 238:0e0dee0000000000dde0ded0d000dde0edd0d0e000e0e0d0dee0e0e000000000
-- 239:ddd0d0000d0000000eee0d000e0000000d0000000dde0e000e000000dee0e000
-- 240:0000033200023324033433223324233303223332000333420000032300000003
-- 241:4330000042333000233342303333243333333330344330003240000030000000
-- 242:0000033200023324034433323324233303323232000334420000032300000003
-- 243:2330000042332000233242303333442232332330342330003240000030000000
-- 244:00000bbb000bbbbb0bbccbbbbbbddccb0ccbbdbb000ccbcc00000bdd0000000b
-- 245:bbb00000ccdbb000ddccbbb0bbbbbbccbccdbbd0bbbcc000ccb00000b0000000
-- 246:00000bbb000bbbbb0bbbccddbbbbbdcc0bccbbbd000dccbb00000dbc0000000d
-- 247:bbb00000bccdb000bbdccbb0dbbbbbccbbccbbd0bbbdc000cbb00000b0000000
-- 248:eeededddd00000d0dd0ddee0000000e00edd00d0000ed0d00dde00d00d0eddde
-- 249:3332322220000020220223300000003003220020000320200223002002032223
-- 250:0000032000002d3233023ed23733e22027ee32003ffd30002f77730022322300
-- 251:0000023000022de3002fe2d203f723e33f73efd3273efe302203e20000002000
-- 252:0002032200273dd20037d3d3002f7d20003ef77303ef22302ef2000003200000
-- 253:00033000023f732002d77d302dfeffd22defffe23ddffee3023de22000032000
-- 254:0022220002dddf302dffeef22df7fef23def7df32deedd7203fff72000332200
-- 255:2220200002000000033202000300000003000000032302000300000033303000
-- </TILES>

-- <SPRITES>
-- 000:00001001000001110000c111000cc111011cc1111014c1110011411300111112
-- 001:11001c0011110cc011111cc011111c40111314003312310012244010222c4000
-- 002:00000000000009a900009a9a000aa9aa0009aaaa009a9aa90099aa9800aaa988
-- 003:00000000aa900a009aa99000aaaaaa00a988aa00a8888aa088844a008884c000
-- 016:001113140111122c111112230111112201111313016113360651166506511555
-- 017:4223300042223000323200003220000061150000511550005115500056165000
-- 018:00a9aa84009aaa84009aa88900aaa989000aa99a009aaa990999aa990999aaa9
-- 019:48899000c88890009898000088800000aa9900009aa990009aa890009a988000
-- 033:cc000000c0000000cc000000c0000000c0000000c000000000000000c0000000
-- 034:c000c000cc0cc000cc0cc0000c0c000000000000000000000000000000000000
-- 035:000000000c00c000cccccc000c00c0000c00c000cccccc000c00c00000000000
-- 036:0000c000c0cccc0c0cc0c0c00cc000000cc000000cc0c0c0c0cccc0c0000c000
-- 037:0c0000c0c0c00cc00c00cc00000cc00000cc00000cc00c00cc00c0c0c0000c00
-- 038:00ccc0000c0c0c000c000000c0c00000c00c0000c000c0c00c000c0000ccc0c0
-- 039:0c000000cc000000cc000000c000000000000000000000000000000000000000
-- 040:0000c00000cc00000cc000000cc000000cc000000cc0000000cc00000000c000
-- 041:c00000000cc0000000cc000000cc000000cc000000cc00000cc00000c0000000
-- 042:0000000000c00000c0c0c0000ccc00000ccc0000c0c0c00000c0000000000000
-- 043:0000000000c0000000c00000ccccc00000c0000000c000000000000000000000
-- 044:000000000000000000000000000000000000000000000000cc0000000c000000
-- 045:000000000000000000000000cccc000000000000000000000000000000000000
-- 046:000000000000000000000000000000000000000000000000cc000000cc000000
-- 047:000cc000000cc00000cc000000cc00000cc000000cc00000cc000000cc000000
-- 048:0440000040040000400440004004000040020000400220004002000004200000
-- 049:0040000004400000004400000040000000420000002000004020200044222000
-- 050:0444000040404000400040000400400000040000004000000400200044222000
-- 051:4444400040004000000400000040000004002000004200004000200004220000
-- 052:0004000000440000004400000404000004044000400200004222200000020000
-- 053:0040400044444000400000000444000000004000404020004000200002220000
-- 054:0044400004004000400000004440000040020000400020002000200002220000
-- 055:4444400040004000000040000000400000020000002000000422000000200000
-- 056:0440000040040000400400000442000040002000402020002000200002220000
-- 057:0044000004004000400040004040400004222000002020004000200002220000
-- 058:00000000cc000000cc0000000000000000000000cc000000cc00000000000000
-- 059:00000000cc000000cc0000000000000000000000cc0000000c00000000000000
-- 060:c000ccc000cc0c000c0c0000c0000000c00000000c0c000000cc0c000000ccc0
-- 061:0000000000000000ccccc0000000000000000000ccccc0000000000000000000
-- 062:0ccc000c00c0cc000000c0c00000000c0000000c0000c0c000c0cc000ccc0000
-- 063:0ccc0c00c000c000c000cc000000c00000cc0c0000c000000000000000c00000
-- 064:0ccccc00c00000c0c00cc0c0c0c0c0c0c0c0c0c0c00ccc000c00000c00ccccc0
-- 065:00cccccc0000ccc0000c0ccc000c0cc000c00cc00cccccc00c000cc0ccc0cccc
-- 066:ccccc0000cc00c00ccc00c000cccccc00cc0000c0cc0cc0c0cc0000cccccccc0
-- 067:00ccccc00ccc000cccc000000cc00cc00cc00cc0ccc000000ccc000c00ccccc0
-- 068:cccccc000cc000c0ccccc00c0cc0000c0cc0000cccccc00c0cc000c0cccccc00
-- 069:cccccccc0cc0000c0cc0c000cccccc000cc0c0000cc000000cc0000ccccccccc
-- 070:ccccccc00cc000cc0cc0c00ccccccc000cc0c0000cc0c0000cc00000cccc0000
-- 071:00ccccc00ccc000cccc00c000cc0ccccccc00c0c0ccc000c00cccccc0000000c
-- 072:cccc0ccc0cc000c0cccccccc0cc000c00cc000c00cc000c00cc000c0cccc0ccc
-- 073:ccccccccc00cc00c00cccc00000cc000000cc00000cccc00c00cc00ccccccccc
-- 074:ccccccccc0c000ccc0c000cc000000cc0c0000ccc0c000ccc0000cc00ccccc00
-- 075:cccc0ccc0cc000c0ccc000c00cc00c00ccccc0000cc00c000cc000c0cccc0ccc
-- 076:cccccc000cc00000cccc00000cc000000cc000000cc0000c0cc0000ccccccccc
-- 077:ccc0c0c00ccc0c0cccc00c0c0cc0c00c0cc0000c0cc000cc0cc0000ccccc00cc
-- 078:ccc0ccc00ccc000cccc000cc0cc0000c0cc000cc0cc0000c0cc0c00cccc00cc0
-- 079:00cccc000cc000c0cc00c00ccc00c00ccc0ccc0ccc00c00c0cc000c000cccc00
-- 080:cccccc000cc000c0ccc0c00c0cc0c00c0cc000c0cccccc000cc00000ccccc000
-- 081:0cc000c0cc00000ccc0ccc0ccc00c00ccc00c00c0cc0c0c000cccc000000c000
-- 082:cccccc000cc000c0ccc0c00c0cc0c00c0cc000c0cccccc000cc00c0ccccc00cc
-- 083:00ccccc00cc00c0ccc000000cc00ccc00ccc00cc000000ccc0c00cc00ccccc00
-- 084:ccccccccc00cc00cc0cccc0cc00cc00c000cc00000cccc00000cc0000cccccc0
-- 085:cccc0ccccc00000cccc000cccc00000ccc00000ccc00000c0cc000c000cccc00
-- 086:cccc0ccc0cc000c0ccc000c00cc00c000cc0c0000cc0c0000ccc0000cccccc00
-- 087:0c0cccccc0000cc0cc00ccccc0000cc0c0c00cc0c00c0cc00c0c0cc000c0cccc
-- 088:ccc00ccc0c0000cc00c000c0000ccc0000ccc0000c000c00cc0000c0ccc00ccc
-- 089:0c00ccccc0000cc0c0000cc00ccccccc00000cc00cc00cc0c000ccc00ccccc00
-- 090:ccccccccc0c000cc000000cc00cc00c00c00cc00cc000000cc000c0ccccccccc
-- 091:cccc00000c000000cc0000000c0000000c000000cc0000000c000000cccc0000
-- 092:020200002c2330000233000000200000000020200002c2330000233000000200
-- 093:cccc000000c0000000cc000000c0000000c0000000cc000000c00000cccc0000
-- 094:000c000000ccc0000cc0cc00cc000cc0c00000c0000000000000000000000000
-- 095:00000000000000000000000000000000000000000000000000000000cccccccc
-- 096:cc000000cc0000000cc000000000000000000000000000000000000000000000
-- 097:0000000000000000000000000ccc00000000c0000cccc000c000c0000ccc0c00
-- 098:0c000000c0000000c0000000c0000000c0cc0000cc00c000c000c000cccc0000
-- 099:0000000000000000000000000ccc0000c000c000c0c00000c000c0000ccc0000
-- 100:000c00000000c0000000c0000000c0000cc0c000c00cc000c000c0000ccc0c00
-- 101:0000000000000000000000000ccc0000c000c0000cc00000c000c0000ccc0000
-- 102:000cc00000c00c0000c000000ccc000000c0000000c00000c0c000000c000000
-- 103:00cc0c000c00c0000c00c00000cc00000c00000000cc0000c000c0000ccc0000
-- 104:0c000000c0000000c0000000c0000000c0cc0000cc00c000c000c000c00c0000
-- 105:0c000000c000000000000000cc000000c0000000c0000000c0c000000c000000
-- 106:00c000000c000000000000000c0000000c00000000c00000c0c000000c000000
-- 107:c00000000c0000000c0c00000cc0c0000c00c0000ccc00000c00c0000c00c000
-- 108:c00000000c000000cc0000000c0000000c0000000c0000000c00000000c00000
-- 109:0000000000000000000000000c0c0000c0c0c000c000c000c000c000c00c0000
-- 110:000000000000000000000000c0cc0000cc00c000c000c000c000c000c00c0000
-- 111:0000000000000000000000000ccc0000c000c000c0c0c000c000c0000ccc0000
-- 112:c00000000c0cc0000cc00c000c000c000cccc0000c0000000c00000000c00000
-- 113:000000c000cc0c000c00cc000c000c0000cccc0000000c0000000c0c000000c0
-- 114:000000000000000000000000c0cc00000c00c0000c0000000c000000ccc00000
-- 115:0000000000000000000000000cccc000c00000000ccc00000000c000cccc0000
-- 116:c00000000c0000000c000000cccc00000c0000000c0000000c00c00000cc0000
-- 117:000000000000000000000000c00c0000c000c000c000c000c000c0000ccc0000
-- 118:000000000000000000000000c000c000c00c0000c00c0000c0c00000cc000000
-- 119:0000000000000000000000000c0c0000c000c000c000c000c0c0c0000c0c0000
-- 120:000000000000000000000000c000c0000c0c000000c000000c0c0000c000c000
-- 121:000000000c00c000c000c000c000c0000cccc0000000c000c000c0000ccc0000
-- 122:000000000000000000000000ccccc000000c000000c000000c000000ccccc000
-- 128:0000000000ccc0000c444400c4324420c424c430c44cc4300444430000223000
-- 129:0005500000d56d0000d00d000d2c23d0d2c2323dd332233e0dd33ee0000de000
-- 130:000000550000d56500dd06600d0000d0d4c44d00dc44ce00d44ce0000dee0000
-- 131:00f00000000f0440000f4c40000dc4000005eff00056000f0560000056000000
-- 132:0000000000000007000007700007700707700770700770070770077070077007
-- 133:0000000070000000077000007007700007700770700770070770077070077007
-- 134:00000ed00000d00e0000e00d000f000e0057000d05600ef05600efe060000e00
-- 135:0000000000000de000007f0d0005600e005600ff0560000e560000ff6000000e
-- 144:0000000000000000000000000000000000000000000000000000000000000007
-- 145:0000000000000000000000000000000000000000000000000000000070000000
-- 146:0000000000000007000007700007700707700770700770070770077070077007
-- 147:0000000070000000077000007007700007700770700770070770077070077007
-- 148:0770077070077007077007707007700707700770700770070770077070077007
-- 149:0770077070077007077007707007700707700770700770070770077070077007
-- 150:0000000000c044000004c400004c400000440c00000000000000000000000000
-- 151:000c0000000040000044c400004c4400000400000000c0000000000000000000
-- 160:0000077000077007077007707007700707700770000770070000077000000007
-- 161:0770000070077000077007707007700707700770700770000770000070000000
-- 162:0770077070077007077007707007700707700770000770070000077000000007
-- 163:0770077070077007077007707007700707700770700770000770000070000000
-- 164:0770077070077007077007707007700707700770000770070000077000000007
-- 165:0770077070077007077007707007700707700770700770000770000070000000
-- 166:000000000020110002c2bb10002bdb1001bdb20001bb2c200011020000000000
-- 167:00020000002c20000012b10001bbdb1001bdbb10001b21000002c20000002000
-- 170:00000000000000000111c0001c1110002c111100421111003211110003111100
-- 171:00000000000000000111c0001c1110002c111100421111003211110001111100
-- 172:000000000111c0001c1110002c11110042111100321111000311110001111100
-- 173:0000000000000000000000000111c0001c1110002c1111004211110032111100
-- 174:000dd00000dccd000dccd0000dcd00000dd00000000000000000000000000000
-- 175:0000000000dd00000dccd000dccd0000dcccd0000ddcd000000dd00000000000
-- 176:8888223288882000888820008888200088882000888830008888200088883000
-- 177:2888888828888888388888882888888838888888388888883888888838888888
-- 178:0000000000000ddf00000def00000df700000df700000def00000fe700000df7
-- 180:0000001100000100000010000000100100010010000100100010010000100111
-- 181:1100000000100000000100001001000001001000010010000010010011100100
-- 182:00000000000000cc00000c4400000c400000c4000000c400000c4000000c4000
-- 183:00000000cc000000444000000c40000000c4000000c40000000c4000000c4000
-- 186:0111150055111500561116006211520002113200023662003262630033562000
-- 187:5511150056111600621112000211520002113200323663003362600056525000
-- 188:5511150056111600621162000211520002523200323663003362600056265000
-- 189:0311110001111500551115005611160062113200021162000262620032525300
-- 190:0000000000dd00000dcd0000dccd00000dccd0000dcccd0000ddccd00000dd00
-- 191:000000000000000000000000000d00000ddcd0000dcccd0000ddccd00000ddd0
-- 192:2222300020000000200000003000000023233000888830008888300088883323
-- 193:2222388800003888000028880000388823222888388888882888888828888888
-- 194:00000fef0dddffef0dffeeee0f77f7e700000fef00000fe700000f7700000000
-- 195:00000000dfd70000feef0000777f000000000000000000000000000000000000
-- 196:0010000000100000001111100000100000001000000011100000001000000011
-- 197:0000010000000100011111000001000000010000011100000100000011000000
-- 198:000c4ccc000c44440000000c00000cc4000004440000000c0000000c00000000
-- 199:cccc400044444000400000004cc0000044400000400000004000000000000000
-- 202:6605200056025030550230330303220033000000000000000000000000000000
-- 203:6625630056265330552020000302300033000000000000000000000000000000
-- 204:6625600056265000550223300303330033000000000000000000000000000000
-- 205:3305200056062000550020300302303333002200000000000000000000000000
-- 206:0000000000000000000000000000000000000006000000650066066566556556
-- 207:0000000000000000000000000000000000000000600066005666560065565660
-- 208:00000000000000000000000000000000000000000000000c0000c00c0000300c
-- 209:00000000000000000000000000000000ccc00000cc30c0002cc02000cc00c000
-- 210:00000000000000000000080000000088000000890000009c0000000c0000000c
-- 211:00000000000000000000000090000000ccc00000cc3000002cc00000cc000000
-- 212:00000000000002220000202400000022000000230000033c0000000c0000000c
-- 213:000000000000000022000080233300903cc00040cc2000602cc00050cc000050
-- 214:0000000000000000000aaa0000aaaaa00aaaa8800aa888400aa848900aa89800
-- 215:000000000000000000000000000aaa0000aaaaa00aaaa8800aa888400aa84890
-- 216:000000000000000000000000000aaa0000aaaaa00aaaa8800aa888400aa84890
-- 217:00000000000aaa0000aaaaa00aaaa8800aa888400aa848900aa8980000a9aa00
-- 218:00000000000000000001110c00c1111c01c11220011222400112423001323200
-- 219:00000000000000000001110c00c1111c01c11220011222400112423001323250
-- 220:000000000001110c00c1111c01c1122001122240011242300132320001331150
-- 221:0000000000000000000000000001110c00c1111c01c112200112224001124230
-- 222:6565566665566666666566666556666606656665000665560000066600000006
-- 223:6665565666666556666656666656655656655660655660006660000060000000
-- 224:0000c00c0000c06500000c060000000c0000000c0000006500000066000000c0
-- 225:5560c000660c000066000000000000005000000060000000c00000000c000000
-- 226:0000088c000008980000c089000c0098000c0089000ca00c000aa09800000988
-- 227:088000008980000089c00000990c0000900c000000ac000080aa000088000000
-- 228:0000000300000c220000c0320000c0330000c00c000c000c0000002200000222
-- 229:0000006023c000c0330ccc603000006000000050000000502000005022000060
-- 230:00a9aa0099a99a9098999a9080998800808888008088aa9089aaaa9099aaaa00
-- 231:0aa8980099a9aa9098a99a9080999a00809988008088aa9089aaaa9099aaaa00
-- 232:0aa8980000a9aa0099a99a9098999a90809988008088aa0080aaaa9089aaaa90
-- 233:00a99a0099999a909899889080888800808888008088aa9089aaaa9099aaaa00
-- 234:0133515055155150561651606215650020563200202266302366563033656500
-- 235:5513515056155160621651002015650020563230232266303366560005656500
-- 236:5513515056165160621565002056220020223230232266303366560005656500
-- 237:0132320001135150551651505615616062163200202266002066563023656530
-- 238:0000000600000665000665650666666665555555666666666556656566655665
-- 239:6000000056600000565660006666666055555556666666665656655656655666
-- 240:00000c0000000c00000003000000005000000c60000000000000000000000000
-- 241:0c00000002000000500000006c00000000000000000000000000000000000000
-- 242:0000088000000890000009c0000000c000000aa0000000000000000000000000
-- 243:98000000c9000000c0000000aa00000000000000000000000000000000000000
-- 244:000002230000032300000330000000c000000330000000000000000000000000
-- 245:2300005033000060c00000503300000000000000000000000000000000000000
-- 246:0aa0aa000aa08000080090000900990009900000000000000000000000000000
-- 247:0aa0aa000aa08000080090000900990009900000000000000000000000000000
-- 248:99a0aa000aa08000080090000900990009900000000000000000000000000000
-- 249:0aa0aa000aa08000080090000900990009900000000000000000000000000000
-- 250:0650550005605500065030000300330003300000000000000000000000000000
-- 251:0650550005605500065030000300330003300000000000000000000000000000
-- 252:0650550005605500065030000300330003300000000000000000000000000000
-- 253:3350550005605500065030000300330003300000000000000000000000000000
-- 254:6556655665555666666555566556655606655666000665560000066600000006
-- 255:6556655666655556655556666556655666655660655660006660000060000000
-- </SPRITES>

-- <MAP>
-- 000:304030403040304030403040304030403040304030403040304030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:314131413141314131413141314131413141314131413141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:324232423242324232423242324232423242324232423242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:304010201020102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:314111211121112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:324212221222122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:304010201020102030403040102010203040304030403040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:314111211121112131413141112111213141314131413141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:324212221222122232423242122212223242324232423242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:304010201020304010201020304010203040102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 025:314111211121314111211121314111213141112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 026:324212221222324212221222324212223242122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 027:304010203040102010201020102010201020102010203040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 028:314111213141112111211121112111211121112111213141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 029:324212223242122212221222122212221222122212223242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 030:304030403040304030403040304030403040304030403040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 031:314131413141314131413141314131413141314131413141000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 032:324232423242324232423242324232423242324232423242000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- 004:001123578acdeeffffeedca875321100
-- 005:011246778bdeffff01234cba987bcdef
-- 006:0011223344556677fedcba9876543210
-- 007:4689bccddca742248bb9445899976688
-- 008:ddb655789bcdddcb432222233469bccc
-- 009:876414678acdedcaacdedca876414678
-- </WAVES>

-- <SFX>
-- 000:0a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a000a00300000000000
-- 001:01073105410361027101810091009100a100b100c100d100d100e100e100e100e100e100f100f100f100f100f100f100f100f100f100f100f100f100a00000000000
-- 002:035023304330532073109300a300b300c300c300d300d300e300e300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300300000000000
-- 003:5300635073009330a300b310c300c350d300d320e300e330e300e310f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300600000000000
-- 004:43007300a300c300d300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300700000000000
-- 005:f00be00cd00ec00fc000b000a00090008000700060005000400040004000400040004000400040004000400040004000400040004000400040004000100000000000
-- 006:62008200a200c200d200e200e200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200400000000000
-- 007:e400d402a4036402340e040d040e040f0400040004000400040004000400040004000400040004000400040004000400040004000400040004000400470000000008
-- 016:04f704e704d604c604b504a504940494048304730463046204510451045004400430043f043e142e142d242d241c341c541b740a940aa409c409f409d05000000000
-- 017:8305b302d307f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300b05000000000
-- 018:00e040b090507506550545044503550275029501a50495078507a502b503a5069506b501c502b505a505c500d501c504b504d500e500d503e503f50fa08000000000
-- 019:03f0c3d0a3a0438003606340b330d320d310d310e300e300e300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300308000000000
-- 020:2739173c073d073f17303730287328723870487058707870a870c8702730573067308700b700c700e700f870f870f870f800f800f800f800f700f700c000eee7ee00
-- 021:397709740972197139706970614e314f2140214031407140b140e14001706170b17001006100b100d10009406940b94009006900b900f900f900f900c080eeeeeeee
-- 022:03975407c407f40613963406f406f40523954404f404f40333925401f400f40e539d740df40cf40c739b940bf40af40ab39ad40af409f409f409f409c03000000000
-- 023:f300f300f300f300f300f300f3000300b300530013001300230043008300b300c300e300e300e300f300f300f300f300f300f300f300f300f300f300308000000000
-- </SFX>

-- <PATTERNS>
-- 000:90001200000000000000000090003c00000000000000000090002400000000000000000090003c00000000000090004c90004c00000090004c00000090001200000090004c00000090002400000000000000000090003c00000090004c00000090001200000000000000000090003c00000000000000000090002400000000000000000090003c00000000000090004c90004c00000090004c00000090001200000090004c00000090002400000090001200000090002400000090004c000000
-- 001:900050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900052000000000000000000900050000000000000000000000000000000000000000000000000000000000000000000600050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600052000000000000000000600050000000000000000000000000000000000000000000000000000000000000000000
-- 002:900050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900052000000000000000000900050000000000000000000000000000000000000000000000000000000000000000000400050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400052000000000000000000400050000000000000000000000000000000000000000000000000000000000000000000
-- 003:900064c00064400066900064c00064400066900064c00064000000000000c00064000000900064000000400066000000900064c00064400066900064400066000000400066000000c00066000000900066000000900064c00064900064c00064600064900064c00064600064900064c00064600064900064000000000000900064000000600064000000c00064000000600064900064c00064600064000000000000600064000000900064000000c00064000000600064c00064600064c00064
-- 004:000000000000000000000000900078000000000000000000000000000000000000000000c0007800000040007a000000000000000000000000000000000000000000000000000000900078000000000000000000000000000000000000000000000000000000000000000000600078000000000000000000000000000000000000000000900078000000000000000000600078000000000000000000000000000000600078000000000000000000000000000000600078000000000000000000
-- 005:900064c00064400066900064c00064400066900064c00064000000000000c00064000000900064000000400066000000900064c00064400066900064400066000000900068000000900066000000900064000000900064c00064900064c00064400064700064c00064400064700064c00064400064700064000000000000700064000000400064000000c00064000000400064700064c00064400064000000000000c00064000000400064000000700064000000400064700064c00064400066
-- 006:00000000000000000000000090007800000000000000000000000000000000000000000040007a000000900078000000c0007800000000000000000090007a00000000000000000000000000000040007a000000000000000000000000000000000000000000000000000000400078000000000000000000700078000000000000000000400078000000000000000000000000000000000000000000000000000000000000000000400078000000000000000000c00076000000000000000000
-- 007:90001200000090004c90001200000090004c90001200000090002400000090003c00000090003c00000090004c00000090001200000090004c00000090001200000090004c00000090002400000090004c90004c90003c00000090004c90004c90001200000090004c90001200000090004c90001200000090002400000090003c00000090003c00000090004c00000090001200000090004c00000090001200000090004c00000090002400000090004c90004c90003c00000090004c90004c
-- 008:900050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700050000000000000000000000000000000000000000000c00050000000000000000000000000000000000000000000400052000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900050000000000000000000000000000000000000000000600050000000000000000000000000000000000000000000
-- 009:900066c00066400068900066c00066400068900066c00066400068900066c00066400068700066000000400066000000700066c00066400068700066c00066400068700066c00066400068700066c00066400068700068000000c00066000000c00068900068400068c00068900068400068c00068900068400068c00068900068400068700068000000400068000000700068c00066400066700068c00066400066700068c00066400066700068c00066400066c00066000000700066000000
-- </PATTERNS>

-- <TRACKS>
-- 000:1005001800001c00001805001c07001804001c06001800000c00000000000000000000000000000000000000000000006f0000
-- 001:800000842a000000000000000000000000000000000000000000000000000000000000000000000000000000000000006f0000
-- </TRACKS>

-- <FLAGS>
-- 000:00900072003100310090007200000000000000000000000000000000000000009000000000000000000000000000000000007200500050005000000000000000900000000000000000000000000000000000000000000000000000000000000090009000900090009000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009400900094009000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a14285d275db13e53952c40ffcd755040403828181820341c792c20482c0830043081daffffe294b0c2566c86343c57
-- </PALETTE>

