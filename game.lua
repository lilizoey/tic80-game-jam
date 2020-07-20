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

local room_palettes={
	default={full_wall=3,half_wall=5,floor=1,door=7,decor={51,32,37},enemies={}}
}

function set_tile(map,x,y,val)
	if not map[x] then map[x]={} end
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
				set_tile(map,x,y,palette.floor)
			end
		end
	end

	for i=1,math.random(1,((x1-x0)*(y1-y0))//10+1) do
		local x=math.random(x0+1,x1-1)
		local y=math.random(y0+1,y1-1)
		local decor=palette.decor[math.random(1,#palette.decor)]
		set_tile(map,x,y,decor)
	end

	for k,v in pairs(doors) do
		set_tile(map,v[1],v[2],palette.door)
		if v[1]==x0 then
			for x=x0+1,(x1-x0)//2 do
				set_tile(map,x,v[2],palette.floor)
			end
		elseif v[1]==x1 then
			for x=x1-1,(x1-x0)//2,-1 do
				set_tile(map,x,v[2],palette.floor)
			end
		elseif v[2]==y0 then
			for y=y0+1,(y1-y0)//2 do
				set_tile(map,v[1],y,palette.floor)
			end
		elseif v[2]==y1 then
			for y=y1-1,(y1-y0)//2,-1 do
				set_tile(map,v[1],y,palette.floor)
			end
		end
	end

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

function largest_room(rooms)
	local largest=1
	for k,room in  pairs(rooms) do
		if (room[3]-room[1])*(room[4]-room[2])>(rooms[largest][3]-rooms[largest][1])*(rooms[largest][4]-rooms[largest][2]) then largest=k end
	end
	return largest
end

function dungeon_generator(xmax,ymax)
	local rooms={{0,0,xmax,ymax}}
	local corridors={}
	local fails=0
	for i=1,20 do
		if fails==3 then break end
		local room_id=largest_room(rooms)
		local room=rooms[room_id]
		local splitted={room}
		local i=1
		while #splitted<2 and i< 20 do
			splitted=split(room[1],room[2],room[3],room[4])
			i=i+1
		end
		if i==20 then fails=fails+1 end
		for k,v in pairs(splitted) do
			table.insert(rooms,v)
		end
		table.remove(rooms,room_id)
	end
	local map={}
	for k,room in pairs(rooms) do
		local doors={}
		if room[1]~=0 then
			local door={room[1]+1,math.random(room[2]+2,room[4]-2)}
			table.insert(doors,door)
			table.insert(corridors,{door[1],door[2],"l",2})
		elseif room[2]~=0 then
			local door={math.random(room[1]+2,room[3]-2),room[2]+1}
			table.insert(doors,door)
			table.insert(corridors,{door[1],door[2],"u",2})
		elseif room[3]~=xmax then
			local door={room[3]-1,math.random(room[2]+2,room[4]-2)}
			table.insert(doors,door)
			table.insert(corridors,{door[1],door[2],"r",2})
		elseif room[4]~=ymax then
			local door={math.random(room[4]+2,room[3]-2),room[4]-1}
			table.insert(doors,door)
			table.insert(corridors,{door[1],door[2],"d",2})
		end
		square_room(map,room_palettes.default,room[1]+1,room[2]+1,room[3]-1,room[4]-1,doors)
	end
	for k,corridor in pairs(corridors) do
		straight_corridor(map,room_palettes.default,corridor[1],corridor[2],corridor[3],corridor[4])
	end
	return map
end

local sample_map
-- palette swapping

local default_palette={}
for i=0,15 do
	local addr=PALETTE_ADDR
	local palette={
		r=peek(addr+i*3),
		g=peek(addr+1+i*3),
		b=peek(addr+2+i*3),
	}
	default_palette[i]=palette
end

local palettes={
	{r=0xFF,g=0xFF,b=0xFF}
}

function swap_palette(p)
	for k,v in pairs(p) do
		poke(PALETTE_ADDR+k*3,v.r)
		poke(PALETTE_ADDR+k*3+1,v.g)
		poke(PALETTE_ADDR+k*3+2,v.b)
	end
end

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
					local dx,dy=calc_iso(ix,iy)
					if fget(sprite,FLOOR_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,0,1,0,0,2,2)
					elseif fget(sprite,HALF_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,0,1,0,0,2,2)
					elseif fget(sprite,FULL_BLOCK) then
						spr_iso(sprite,dx+sx,dy+sy,0,1,0,0,2,3)
					end
					if is_visible(ix,iy) == "was visible" then
						if fget(sprite,FLOOR_BLOCK) then
							spr_iso(263,dx+sx,dy+sy,0,1,0,0,2,2)
						elseif fget(sprite,HALF_BLOCK) then
							spr_iso(261,dx+sx,dy+sy,0,1,0,0,2,2,1)
						elseif fget(sprite,FULL_BLOCK) then
							spr_iso(259,dx+sx,dy+sy,0,1,0,0,2,3,1) 
						end
					end
				end
			end
		end
	end
	tick()
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
		if fget(iso_mget(v[1],v[2]),OPAQUE_FLAG) and not (x1==v[1] and y1==v[2]) then
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
	sprite=257,
	facing=0,
	turn="player",
	hp=4,max_hp=4,alive=true
})

function player:do_turn()
	local did_move=false
	local obj = nil

	if btnp(0,20,5) and not is_solid(self.x,self.y-1) then
		obj=self:move(self.x,self.y-1)
		self.facing=0
		did_move=true
	elseif btnp(1,20,5) and not is_solid(self.x,self.y+1) then
		obj=self:move(self.x,self.y+1)
		self.facing=1
		did_move=true
	elseif btnp(2,20,5) and not is_solid(self.x-1,self.y) then
		obj=self:move(self.x-1,self.y)
		self.facing=1
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

	return did_move
end

function player:draw()
	local ix,iy=calc_iso(self.x,self.y)
	spr_iso(self.sprite,
		ix,iy,
		0,1,self.facing,0,2,3,1)
end

function player:attack(obj)
	obj:hit()
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

-- enemy code

function create_enemy(x,y,sprite,hp,atk)
	local enemy = Object.new({
		x=x,y=y,sprite=sprite,
		enemy=true,hp=hp,atk=atk or 1,
		turn="enemy",state="wander"
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
	end

	function enemy:hit()
		sfx_enemy_hit()
		self.hp=self.hp-1
		if self.hp<1 then
			self:die()
		end
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
	local enemy=create_enemy(x,y,465,1)
end

function link_the_skeleton(x,y)
	local enemy=create_enemy(x,y,467,2)
end

function turtleneck_skeleton(x,y)
	local enemy=create_enemy(x,y,469,1,2)
end

rave_skeleton(3,3)
link_the_skeleton(4,4)
turtleneck_skeleton(5,5)
-- animation buffer

local animation_buffer={}

local sample_animation={frames={{t=45,s=1},{t=45,s=2}}}

function add_animation(animation)
	table.insert(animation_buffer)
end

function animate()

end

--- ui
-- ui elements


-- ui logic

function show_resource_bar(s,x,y,res,max_res,colorkey,scale)
	scale=scale or 1
	for x=x,x+(max_res//2 - 1)*(9*scale),(9*scale) do
		if res>1 then
			spr(s,x,y,colorkey,scale)
			res=res-2
		elseif res==1 then
			spr(s+1,x,y,colorkey,scale)
			res=res-1
		else
			spr(s+2,x,y,colorkey,scale)
		end
	end
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

local SIDE_LEFT=0
local SIDE_RIGHT=1

local Dialogue={
	mt={},
	pt={margin=5,text_margin=2,rows=3,sprite=3}
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
		x=x+w-(self.sprite*8+self.text_margin*2)
	end
	return x,y,self.sprite*8+self.text_margin*2,self.sprite*8+self.text_margin*2
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
	self.lines=lines
end

function Dialogue.pt:draw()
	local x,y,w,h=self:dimensions()
	local sx,sy,sw,sh=self:sprite_dimensions()
	rect(x,y,w,h,0)
	rectb(x,y,w,h,12)
	spr(self.head,sx+self.text_margin,sy+self.text_margin,0,self.sprite,self.side)
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
	if not self.lines[(self.index-1)*self.rows+1] then
		return true
	end
	self.sound()
	sfx_stop_after(60)
	return false
end

function Dialogue.pt:is_complete()
	return not self.lines[(self.index-1)*self.rows+1]
end

local Conversation={
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
		if self:get_dialogue() then self:get_dialogue().sound() end
	end
end

local current_conversation=Conversation.new()
current_conversation:add_dialogue(Dialogue.new(400,SIDE_LEFT,"What the fuck did you just fucking say about me, you little bitch? I'll have you know I graduated top of my class in the Navy Seals, and I've been involved in numerous secret raids on Al-Quaeda, and I have over 300 confirmed kills.",sfx_demon_girl_voice))
current_conversation:add_dialogue(Dialogue.new(401,SIDE_RIGHT,"I am trained in gorilla warfare and I'm the top sniper in the entire US armed forces. You are nothing to me but just another target. ",sfx_slime_girl_voice))
current_conversation:add_dialogue(Dialogue.new(400,SIDE_LEFT,"I will wipe you the fuck out with precision the likes of which has never been seen before on this Earth, mark my fucking words. ",sfx_demon_girl_voice))

function OVR()
	show_resource_bar(384,1,1,player.hp,player.max_hp,4,2)
	if current_conversation then current_conversation:draw() end
end

sample_map = dungeon_generator(60,60)

-- main
local playing_music=false
function TIC()
	cls()
	if not playing_music then
		music(0,0,0,true,true)
		playing_music=true
	end
		clear_visible()
	start_draw()
	take_turns()
	shadow_casting(player,6)
	update_camera(camera,player)
	local dx,dy=player.x,player.y
	if dx-8<0 then dx=0 else dx=dx-8 end
	if dy-8<0 then dy=0 else dy=dy-8 end
	map_iso(dx,dy,16,16,0,0)
	draw_objects()
	final_draw()
	sfx_tick()
	if btnp(4) and current_conversation then
		current_conversation:next()
	end
end

-- <TILES>
-- 001:000000000000000000000000000000000000000000000000000000000000000d
-- 002:00000000000000000000000000000000000000000000000000000000d0000000
-- 003:0000000f00000ffe000ffeef0ffeffeefeefeeeedddeeeeededddeeeddededde
-- 004:f0000000fff00000efeff000eeeeeff0eeeefeffeeeeeddfeeeddeefeddedeef
-- 005:0000000f00000fff000fffee0fffefeefefeeeeedddeeeeeddeddeeededdedde
-- 006:f0000000eff00000fefff000eeefeff0eeeeeeffeeeeeddfeeeddeffeddeefef
-- 007:0000000000000000000000000000660000066666000666660006566600065655
-- 008:0000000000000000000000000000000000000000660000006666000066660000
-- 017:00000dde000ddeef0ddeeffefeeddeee0ffeedde000ffeed00000ffe0000000f
-- 018:edd00000feedd000effeedd0eeeffeededdeeff0deeff000eff00000f0000000
-- 019:ddeedeefdeeeeeefddeeeeefdeeeeeefdeeeeeffdeeeeeefddeeeeffddeeeeff
-- 020:ddedeeefddeeeeefdeeeeeffddeeeeffdeeeeeefddeeeeefddeeefefdeeeeeff
-- 021:ddeeeeefddeeeeefdeeeeeffdeeefeff0fffefef000ffeff00000fff0000000f
-- 022:ddedeeefddeeefefdedeeeffddeefeffdeefeff0dfeff000dff00000d0000000
-- 023:0006555500065655000656550006565500065644000654560006546600066644
-- 024:6566000065660000556600006566000065660000456600004666000065660000
-- 032:0000000000000000000000000000000000000000000000000000000000000006
-- 033:0000000000000000000000000000000000000000000000000000000060000000
-- 035:ddeeeeffdeeeeeefddeeefefdeefeeff0ffeffef000ffeff00000fff0000000f
-- 036:deeeeeefddeeeeffdeeeefffdeeeeeffdeefeff0defff000dff00000d0000000
-- 037:0000000600000665000665650666666665555555666666666556656566655665
-- 038:6000000056600000565660006666666055555556666666665656655656655666
-- 039:0006665500065655000666650006566500006656000000660000000000000000
-- 040:6666000066660000656600006666000065660000656600006666000000660000
-- 048:0000066500066556066556656556655606655665000665550000055600000005
-- 049:5660000065566000566555506555566555566550566550006550000050000000
-- 051:0000000f00000ffe000ffeff0ffeefeefeefeeeedddeeeeeddeddeeededeedde
-- 052:f0000000fff00000efeff000eefefff0eedeefefeeededdfdeeddeefeddedeff
-- 053:6556655665555666666555566556655606655666000665560000066600000006
-- 054:6556655666655556655556666556655666655660655660006660000060000000
-- 067:dffefeff0ddfffef0feddfff00ffeddd00dffeed00de8ffd00de99ef0feddaef
-- 068:ddefeff0ddeffdd0dffdded0fddeef00fedfff00fff9ef00de8aed00de9dded0
-- 083:dffeeddfdddffedddedddffdddededdd0ffeeeef000ffeff00000fff0000000f
-- 084:dddeeffffefffddffffddefffddeefefdeefeff0dedff000dff00000d0000000
-- 225:0000000000000000000000000000000000000000000000000000000000000003
-- 226:0000000000000000000000000000000000000000000000000000000030000000
-- 227:0000000000000000000000000000000000000000000000000000000000000003
-- 228:0000000000000000000000000000000000000000000000000000000030000000
-- 241:0000033200023324033433223324233303223332000333420000032300000003
-- 242:4330000042333000233342303333243333333330344330003240000030000000
-- 243:0000033200023324034433323324233303323232000334420000032300000003
-- 244:2330000042332000233242303333442232332330342330003240000030000000
-- </TILES>

-- <SPRITES>
-- 001:000000000000000000000001000000c1000001c1000001120000011200000132
-- 002:0000000000000000110c0000111c000012200000224000004230000032000000
-- 003:0000000f000000f0000f0f0f00f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 004:00000000f0f000000f0f0000f0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 005:0000000f000000f0000f0f0f00f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 006:00000000f0f000000f0f0000f0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 008:00000000000000000000000000000000000000000000000000000000f0000000
-- 017:0000013300005515000056160000621500002056000020220000236600003365
-- 018:5150000051500000516000006500000023000000663000005630000065000000
-- 019:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 020:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 021:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 022:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 023:00000f0f0000f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 024:0f000000f0f0f0000f0f0f00f0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 033:0000065000000560000006500000030000000330000000000000000000000000
-- 034:5500000055000000300000003300000000000000000000000000000000000000
-- 035:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 036:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 037:0c0000c0c0c00cc00c00cc00000cc00000cc00000cc00c00cc00c0c0c0000c00
-- 038:00ccc0000c0c0c000c000000c0c00000c00c0000c000c0c00c000c0000ccc0c0
-- 039:0c000000cc000000cc000000c000000000000000000000000000000000000000
-- 040:0000c00000cc00000cc000000cc000000cc000000cc0000000cc00000000c000
-- 041:c00000000cc0000000cc000000cc000000cc000000cc00000cc00000c0000000
-- 042:0000000000c00000c0c0c0000ccc00000ccc0000c0c0c00000c0000000000000
-- 043:0000000000cc000000cc0000cccccc00cccccc0000cc000000cc000000000000
-- 044:000000000000000000000000000000000000000000000000cc0000000c000000
-- 045:000000000000000000000000cccc000000000000000000000000000000000000
-- 046:000000000000000000000000000000000000000000000000cc000000cc000000
-- 047:000cc000000cc00000cc000000cc00000cc000000cc00000cc000000cc000000
-- 048:000000000000000000c000000cccc000c000c000c0c0cc00c000c0000ccc0000
-- 049:00c000000cc0000000cc000000c0000000cc000000c00000c0c0c000ccccc000
-- 050:0ccc0000c0c0c000c000c0000c00c000000c000000c000000c00c000ccccc000
-- 051:ccccc000c000c000000c000000c000000c00c00000cc0000c000c0000ccc0000
-- 052:000c000000cc000000cc00000c0c00000c0c0000c00c0c00ccccc000000c0000
-- 053:00c0c000ccccc000c00000000ccc00000000c000c0c0c000c000c0000ccc0000
-- 054:0022200002002000200000002222000022022000202020002202200002220000
-- 055:ccccc000c000c0000000c000cccccc00c00c0c0000c000000c000000c0000000
-- 056:000000000000cc00000c00c00ccc00c0c000cc00c0c0c000c000c0000ccc0000
-- 057:00cc00000c00c000c00ccc000c00c00000cccc000000c000c000c0000ccc0000
-- 058:00000000cc000000cc0000000000000000000000cc000000cc00000000000000
-- 059:00000000cc000000cc0000000000000000000000cc0000000c00000000000000
-- 060:c000ccc000cc0c000c0c0000c0000000c00000000c0c000000cc0c000000ccc0
-- 061:00000000cccccc00cccccc000000000000000000cccccc00cccccc0000000000
-- 062:0ccc000c00c0cc000000c0c00000000c0000000c0000c0c000c0cc000ccc0000
-- 063:0ccc0c00c000c000c000cc000000c00000cc0c0000c000000000000000c00000
-- 064:0ccccc00c00000c0c00cc0c0c0c0c0c0c0c0c0c0c00ccc000c00000c00ccccc0
-- 065:00cccccc0000ccc0000c0ccc000c0cc000c00cc00cccccc00c000cc0ccc0cccc
-- 066:ccccc0000cc00c00ccc00c000cccccc00cc0000c0cc0cc0c0cc0000cccccccc0
-- 067:00ccccc00ccc000cccc000000cc0cc000cc0cc00ccc000000ccc000c00ccccc0
-- 068:cccccc000c0000c0cccc000c0c00000c0c00000ccccc000c0c0000c0cccccc00
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
-- 081:0cc000c0cc00000ccc00000ccc0ccc0ccc00c00c0cc0c0c000cccc000000c000
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
-- 092:c000c000cc0cc000cc0cc0000c0c000000000000000000000000000000000000
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
-- 116:00c000000c0000000c000000cccc00000c0000000c0000000c00c00000cc0000
-- 117:000000000000000000000000c00c0000c000c000c000c000c000c0000ccc0000
-- 118:000000000000000000000000c000c000c00c0000c00c0000c0c00000cc000000
-- 119:0000000000000000000000000c0c0000c000c000c000c000c0c0c0000c0c0000
-- 120:c000c0000c00c0000c0c000000c0000000c000000c0c0000c00c0000c000c000
-- 121:000000000c00c000c000c000c000c0000cccc0000000c000c000c0000ccc0000
-- 122:000000000000000000000000ccccc000000c000000c000000c000000ccccc000
-- 128:4411114444122144111221111222222112222221111221114412214444111144
-- 129:4411114444120144111201111222000112220001111201114412014444111144
-- 130:4411114444100144111001111000000110000001111001114410014444111144
-- 144:000000000001110c00c1111c01c1122001122240011242300132320001335150
-- 145:000000000000000000aaa0000aaaaa00aaaa8800aa888400aa848900aa898000
-- 205:0000000000000000000000000000000000000000000000000000002000000032
-- 206:0000000000220220022222220222222203222223003222302003230030003000
-- 207:0000000000000000000000000000000000000000000000002020000032300000
-- 209:00000000000000000000000000000000000000000000000c0000c00c0000300c
-- 210:00000000000000000000000000000000ccc00000cc30c0002cc02000cc00c000
-- 211:00000000000000000000080000000088000000890000009c0000000c0000000c
-- 212:00000000000000000000000090000000ccc00000cc3000002cc00000cc000000
-- 213:00000000000002220000202400000022000000230000033c0000000c0000000c
-- 214:000000000000000022000080233300903cc00040cc2000602cc00050cc000050
-- 215:00000000000000000000000a000000aa00000aaa00000aa800000aa800000aa8
-- 216:0000000000000000aa000000aaa00000a8800000884000004890000098000000
-- 217:000000000000000000000001000000c1000001c1000001120000011200000132
-- 218:0000000000000000110c0000111c000012200000224000004230000032000000
-- 221:00000003000000000000000a000000aa00000aaa00000aa800000aa800000aa8
-- 222:0000000000000000aa000c01aaa00c11a8800022884000424890003298000002
-- 223:03000000000000001100000011c0000011c10000221100004211000032310000
-- 225:0000c00c0000c06500000c060000000c0000000c0000006500000066000000c0
-- 226:5560c000660c000066000000000000005000000060000000c00000000c000000
-- 227:0000088c000008980000c089000c0098000c0089000c900c0009909800000988
-- 228:088000008980000089c00000990c0000900c0000009c00008099000088000000
-- 229:0000000300000c220000c0320000c0330000c00c000c000c0000002200000222
-- 230:0000006023c000c0330ccc603000006000000050000000502000005022000060
-- 231:000000a8000099a900009899000080990000808800008088000089aa000099aa
-- 232:aa0000009aa0000099a000008800000088000000aa900000aa900000aa000000
-- 233:0000013300005515000056160000621500002056000020220000236600003365
-- 234:5150000051500000516000006500000023000000663000005630000065000000
-- 237:000000a8000099a900009899000080990000808800008088000089aa000099aa
-- 238:aa0000519aa0005199a000618800000588000003aa900036aa900036aa000005
-- 239:5331000055155000561650006512600026502000622020005663200065633000
-- 241:00000c0000000c00000003000000005000000c60000000000000000000000000
-- 242:0c00000002000000500000006c00000000000000000000000000000000000000
-- 243:0000088000000890000009c0000000c000000990000000000000000000000000
-- 244:98000000c9000000c00000009900000000000000000000000000000000000000
-- 245:000002230000032300000330000000c000000330000000000000000000000000
-- 246:2300005033000060c00000503300000000000000000000000000000000000000
-- 247:00000aa000000aa0000008000000090000000990000000000000000000000000
-- 248:aa00000080000000900000009900000000000000000000000000000000000000
-- 249:0000065000000560000006500000030000000330000000000000000000000000
-- 250:5500000055000000300000003300000000000000000000000000000000000000
-- 253:00000aa00ffffaaf0fff78770ff779770ff779970fff77770fffffff0fffffff
-- 254:aa0000058ffffff5977fff779977f7737777f777777fff77ffffffffffffffff
-- 255:505600005f65ffff37567fff377377ff773377ff77777fffffffffffffffffff
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
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000300000000000
-- 001:01073105410361027101810091009100a100b100c100d100d100e100e100e100e100e100f100f100f100f100f100f100f100f100f100f100f100f100a00000000000
-- 002:035023304330532073109300a300b300c300c300d300d300e300e300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300300000000000
-- 003:5300635073009330a300b310c300c350d300d320e300e330e300e310f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300600000000000
-- 004:43007300a300c300d300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300700000000000
-- 005:f00be00cd00ec00fc000b000a00090008000700060005000400030001000000000000000000000000000000000000000000000000000000000000000100000000000
-- 006:62008200a200c200d200e200e200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200f200400000000000
-- 007:e400d402a4036402340e040d040e040f0400040004000400040004000400040004000400040004000400040004000400040004000400040004000400470000000008
-- 016:04f704e704d604c604b504a504940494048304730463046204510451045004400430043f043e142e142d242d241c341c541b740a940aa409c409f409d05000000000
-- 017:53057302a307f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300b05000000000
-- 018:00e040b090507506550545044503550275029501a50495078507a502b503a5069506b501c502b505a505c500d501c504b504d500e500d503e503f50fa08000000000
-- 019:03f0c3d0a3a0438003606340b330d320d310d310e300e300e300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300f300308000000000
-- 020:c739a73ca73db73fc730d730c873b872a870a870b870c870e870f870a730a730b730c700d700e700f700f870f870f870f800f800f800f800f700f700c000eee7ee00
-- 021:c977a974a972b971c970d970c14eb14fa140a140b140c140e140f140a170c170e170a100c100e100f100a940c940e940a900c900e900f900f900f900c080eeeeeeee
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
-- 000:009080726231000000000000000000000080806262000000000000000000000090000062623100000000000000000000000000720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000b000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53952c40ffcd7550404038281818203c1c792c20482c0830045d1855ffffe294b0c2566c86343c57
-- </PALETTE>

