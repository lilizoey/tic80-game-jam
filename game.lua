-- title:  game title
-- author: LAZK
-- desc:   short description
-- script: lua

-- constants

local SOLID_FLAG = 1
local OPAQUE_FLAG = 2
local HALF_BLOCK = 3
local FULL_BLOCK = 4

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

-- 

function calc_iso(x,y)
	local xx=8*x
	local xy=4.5*x
	local yx=-8*y
	local yy=4.5*y 
	return xx+yx,xy+yy
end

function map_iso(x,y,w,h,sx,sy)
	for ix=x,x+w do
		for iy=y,y+h do
			if fget(iso_mget(ix,iy),0) then
				if is_visible(ix,iy) then
					local dx,dy=calc_iso(ix,iy)
					spr_iso(iso_mget(ix,iy),dx+sx,dy+sy,0,1,0,0,2,2)
					if is_visible(ix,iy) == "was visible" then
						if fget(iso_mget(ix,iy),HALF_BLOCK) then
							spr_iso(261,dx+sx,dy+sy,0,1,0,0,2,2)
						elseif fget(iso_mget(ix,iy),FULL_BLOCK) then
							spr_iso(259,dx+sx,dy+sy,0,1,0,0,2,2,1)
						end
					end
				end
			end
		end
	end
end

function iso_mget(x,y)
	return mget(x*2,y*2)
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
	pre_spr(index,x-camera.x,y-camera.y,colorkey,scale,flip,rotate,w,h,z)
end

-- player

local player={
	x=1,y=1,
	sprite=257
}

function draw_player(p)
	local ix,iy=calc_iso(p.x,p.y)
	spr_iso(p.sprite,
		ix,iy,
		0,1,0,0,2,2,1)
end

function update_player(p)
	if btnp(0) then
		p.y=p.y-1
	elseif btnp(1) then
		p.y=p.y+1
	end
	
	if btnp(2) then
		p.x=p.x-1
	elseif btnp(3) then
		p.x=p.x+1
	end
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
	turn_id=(turn_id+1)%#turn_order + 1
end

function player_turn()
	if turn()~="player" then
		return
	end
	local did_move=false
	if move_player(player) then
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
	next_turn()
end

-- movement

function is_solid(x,y)
	return fget(iso_mget(x,y),SOLID_FLAG)
end

function move_player(p)
	local did_move=false

	if btnp(0) and not is_solid(p.x,p.y-1) then
		p.y=p.y-1
		did_move=true
	elseif btnp(1) and not is_solid(p.x,p.y+1) then
		p.y=p.y+1
		did_move=true
	end
	if btnp(2) and not is_solid(p.x-1,p.y) then
		p.x=p.x-1	
		did_move=true
	elseif btnp(3) and not is_solid(p.x+1,p.y) then
		p.x=p.x+1
		did_move=true
	end

	return did_move
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
		if fget(iso_mget(v[1],v[2]),OPAQUE_FLAG) then
			return false
		end
	end
	return true
end

function	shadow_casting(p,range)
	for x=p.x-range,p.x+range do
		for y=p.y-range,p.y+range do
			if can_see(p.x,p.y,x,y) then
				set_visible(x,y)
			end
		end
	end
end
-- main

function TIC()
	cls()
	clear_visible()
	start_draw()
	enemy_turn()
	player_turn()
	shadow_casting(player,4)
	update_camera(camera,player)
	local dx,dy=player.x,player.y
	if dx-16<0 then dx=0 else dx=dx-16 end
	if dy-16<0 then dy=0 else dy=dy-16 end
	map_iso(dx,dy,32,32,0,0)
	draw_player(player)
	final_draw()
	
end

-- <TILES>
-- 001:000000000000000000000000000000000000000000000000000000000000000d
-- 002:00000000000000000000000000000000000000000000000000000000d0000000
-- 003:0000000d00000dde000ddede0ddeeeeeddeedeefdddeeededdedddeedeeeedde
-- 004:f0000000eff00000deeff000eefeeff0eeeffeffeeeeefffefeffeeffffeeeef
-- 017:00000dde000ddeed0dddedeedeeeeeee0ffeefee000ffeef00000ffe0000000f
-- 018:edd00000ededd000eedeedd0deeeeeefeeefeff0efeff000eff00000f0000000
-- 019:ddedeeefddeeedefdeedeeffddeeeeef0ffeefef000ffeef00000fff0000000f
-- 020:fedeeeeffeeefefffdeeeeeffeeeffffffefeff0feeff000fff00000f0000000
-- 034:00000000000000000000000000000000000000000000000000000000f0000000
-- 035:0000000f000000f0000f0f0f00f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 036:00000000f0f000000f0f0000f0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 049:00000f0f0000f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 050:0f000000f0f0f0000f0f0f00f0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 051:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 052:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 144:000000000000000000000000000000000000000000000000000000000000000d
-- 145:00000000000000000000000d00000dde000ddeed0dddedeedeeeeeeedffeefee
-- 146:0000000000000000d0000000edd00000ededd000eedeedd0deeeeeefeeefeff0
-- 160:00000dde000ddeed0dddedeedeeeeeee0ffeefee000ffeef00000ffe0000000f
-- 161:eddffeefeeeeeffeeeeeeddfeeeeeeefeeefeff0efeff000eff00000f0000000
-- 162:efeff000eff00000f00000000000000000000000000000000000000000000000
-- </TILES>

-- <SPRITES>
-- 001:000000020000022200022222022222222222222222fff2f222f222f222f222ff
-- 002:2000000022200000222220002222222022222222f2fff222f2f2f222f2ff2222
-- 003:0000000f000000f0000f0f0f00f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 004:00000000f0f000000f0f0000f0f0f0f00f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0
-- 006:00000000000000000000000000000000000000000000000000000000f0000000
-- 017:22f222f222f222f222fff2f22222222202222222000222220000022200000002
-- 018:f2f2f222f2f2f222f2f2f2222222222222222220222220002220000020000000
-- 019:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 020:0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 021:00000f0f0000f0f00f0f0f0ff0f0f0f00f0f0f0f0000f0f000000f0f00000000
-- 022:0f000000f0f0f0000f0f0f00f0f0f0f00f0f0f00f0f0f0000f000000f0000000
-- 208:00000000000000000000000b000000ca00000acb00000ba200000ab200000b32
-- 209:0000000000000000aa0c0000abbc0000b2200000224000004230000032000000
-- 224:00000b33000088b8000089a9000092a800002989000029220000239900003398
-- 225:8b0000008b8000008a2000009820000023200000992000008930000098000000
-- 240:0000098900077897077779877777739707777337000777770000077700000007
-- 241:8870000088777000397777703377777777777770777770007770000070000000
-- </SPRITES>

-- <MAP>
-- 000:304030403040304030403040304030403040304030403040304030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:314131413141314131413141314131413141314131413141314131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:304010201020102010201020102010201020102030403040304030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:314111211121112111211121112111211121112131413141314131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:304010201020102010201020102030401020102030401020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:314111211121112111211121112131411121112131411121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:304010201020102010201020102010203040304030401020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:314111211121112111211121112111213141314131411121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:304010201020102010201020102010203040102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:314111211121112111211121112111213141112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 018:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 019:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 020:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:304010201020102010201020102010201020102010201020102030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 025:314111211121112111211121112111211121112111211121112131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 026:304030403040304030403040304030403040304030403040304030400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 027:314131413141314131413141314131413141314131413141314131410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200300000000000
-- 001:010611054103510171008100810081009100910091009100910091009100910091009100910091009100910091009100910091009100910091009100200000000000
-- 002:020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200020002000200300000000000
-- 003:030713043302630f830d930ba309a308b308c308d308e308e308f308f308f308f308f308f300f300f300f300f300f300f300f300f300f300f300f300400000000000
-- </SFX>

-- <PATTERNS>
-- 000:b00014000000000000000000600016000000000000000000b00014000000000000000000600016000000000000000000800014000000000000000000b00014000000000000000000800014000000000000000000b00014000000000000000000400014000000000000000000800014000000000000000000400014000000000000000000800014000000000000000000600014000000000000000000a00014000000000000000000600014000000000000000000600016000000000000000000
-- 001:b00026f00026800028000000b00026f00026800028000000b00026f00026800028000000b00026f00026800028000000800026b00026f00026000000800026b00026f00026000000800026b00026f00026000000800026b00026f00026000000400026800026b00026000000400026800026b00026000000400026800026b00026000000400026800026b00026000000600026a00026d00026000000600026a00026d00026000000600026a00026d00026000000600026a00026d00026000000
-- 002:000000000000b0003e000000600038000000b0003e00000000000000000090003e00000060003800000090003e00000000000000000080003e000000b0003800000080003e00000000000000000080003e000000b0003800000040003e00000000000000000040003e00000080003800000040003e00000000000000000040003e00000080003800000080003e00000000000000000080003e000000a00038000000a0003e000000000000000000a0003e00000060003a000000a0003e000000
-- </PATTERNS>

-- <TRACKS>
-- 000:180300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <FLAGS>
-- 000:00908071410000000000000000000000008080414100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53952c40ffcd757d3cee38b764257179753830612c247934715d1855f4f4f494b0c2566c86333c57
-- </PALETTE>

