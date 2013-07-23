--[[
==README==

Lua Interpreter

This allows you to run Lua code on-the-fly on an .ass file. The code will
be applied to all the selected lines. A simple API is provided to make
modifying line properties more efficient.

Calling it a "Lua interpreter" may be a misnomer, but I can't think of
anything better at the moment.

I'll write a more detailed documentation of all the functions and the
runtime environment of the interpreter later. Here are the basics:

The code the user inputs is run for each "section" of text, as marked by
the override blocks. A "section" of text is defined as the part of the
line that has all the same properties. For example, this line:

Never gonna {\fs200}give {\alpha&H55&}you up

has three sections. The first section is "Never gonna " and contains all
default properties. The second section is "{\fs200}give ". All text in
this section has font size 200, and default properties otherwise. The
third and last section is "{\alpha&H55&}you up", which has font size 200,
an alpha of 55 hex, and default properties otherwise.

Any code you input into the interpreter will thus run once for each of
these three sections, changing the properties as appropriate.

Functions are as follows:

modify(tag, method)
	Modify tag using method. tag is a string that indicates the override
	tag (property) that you want to modify. method is a function that
	dictates how the modification is done. For example, to double the
	font size, do:
	
	modify("fs",multiply(2))

modify_line(property, method)
	Works like modify(), but acts on line properties, not override tags.
	For example, to modify the layer of a line:
	
	modify_line("layer",add(1))
	
	For a list of line properties that can be modified, see:
	http://docs.aegisub.org/3.0/Automation/Lua/Modules/karaskel.lua/#index12h3

add(...)
	Returns a function that will add the given values. Can have multiple
	parameters. For example, to expand a rectangular clip by 10 pixels on
	all sides, assuming the first two coordinates represent top left and
	the last two coordinates represent bottom right, do:
	
	modify("clip",add(-10,-10,10,10))
	
	This will add -10, -10, 10, and 10, in that order, to the four
	parameters of \clip. There is no subtract() function; simply add a
	negative number to subtract.
	
multiply(...)
	Works like add(). There is no divide() function. Simply multiply by
	a decimal or a fraction. Example:
	
	modify("fscx",multiply(0.5))

replace(x)
	Returns a function that returns x. When used inside modify(), this
	will effectively replace the original parameter of the tag with x.
	
	modify("fn",replace("Comic Sans MS"))

append(x)
	Returns a function that appends x to the parameter. For example:
	
	modify_line("actor",append(" the great"))
	
	I'm not sure why I wrote this function either. Completeness' sake,
	perhaps.

get(tag)
	Returns the parameter of the tag. If the tag has multiple parameters,
	they are returned as a table. Example:
	
	main_color=get("c")

remove(...)
	Removes all the tags listed. Example:
	
	remove("bord","shad")

select()
	Adds the current line to the final selection. If this function is
	never used, the original selection will be returned.

duplicate()
	DO NOT USE UNLESS YOU KNOW WHAT YOU ARE DOING. This will insert a
	copy of the current line after the current line. Beware of recursion!
	If you do not put some sort of if statement around duplicate(), then
	your first line will be duplicated, then the duplicate will be
	duplicated, then the duplicate of the duplicate will be duplicated,
	and you end up in an infinite loop. I suggest you use the function
	like this:
	
	if i%2==1 then
		duplicate()
		
		--Code to run on the original line
		
	else
	
		--Code to run on the duplicate line
	
	end
	
	Note that "once per line" functions such as duplicate() are run at
	the end of the rest of the execution, but before changes are saved.
	In other words, duplicate() will always create a line that looks like
	your current line did originally, before you modified it at all.


Global variables are as follows:

i
	This is the index within your selection. In other words, when the
	code is being run on the first line, i will have the value 1. When
	the code is being run on the third line, i will have the value 3.
	In the code example under duplicate() above, i will be odd for all
	of the original lines and even for all of the duplicates, thus
	the check "i%2==1" is made.

li
	This is the line number of the current line.

j
	This is the number (counting from 1) of the section that the code is
	currently looking at.

state
	This is a table containing the current state of the line, indexed by
	tag name. For example, to find out what the current x scaling is, use:
	
	state["fscx"]

pos
	This is a table (or object) with two fields: x and y. Use pos.x to
	access the x coordinate and pos.y to access the y coordinate. The
	coordinates are guaranteed to match the line's position on screen,
	even if no position is defined in-line.

org
	Like pos, but for the origin.

]]

include("karaskel.lua")
include("utils.lua")

script_name="Lua Interpreter"
script_description="Run Lua code on-the-fly"
script_version="alpha 0.2"

dialog_conf=
{
	{class="label",label="Enter code below:",x=0,y=0,width=10,height=1},
	{class="textbox",name="code",x=0,y=1,width=40,height=6}
}

--Convert float to neatly formatted string
function float2str(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

--Sanitizes string for use in gsub
function esc(str)
	str=str:gsub("%%","%%%%")
	str=str:gsub("%(","%%%(")
	str=str:gsub("%)","%%%)")
	str=str:gsub("%[","%%%[")
	str=str:gsub("%]","%%%]")
	str=str:gsub("%.","%%%.")
	str=str:gsub("%*","%%%*")
	str=str:gsub("%-","%%%-")
	str=str:gsub("%+","%%%+")
	str=str:gsub("%?","%%%?")
	return str
end

--Returns a function that adds by each number
function add(...)
	x=arg
	return function(...)
			y=arg
			z={}
			for i,_ in ipairs(y) do
				y[i]=tonumber(y[i]) or 0
				x[i]=tonumber(x[i]) or 0
				z[i]=y[i]+x[i]
			end
			return unpack(z)
		end
end

--Returns a function that multiplies by each number
function multiply(...)
	x=arg
	return function(...)
			y=arg
			z={}
			for i,_ in ipairs(y) do
				y[i]=tonumber(y[i]) or 0
				x[i]=tonumber(x[i]) or 0
				z[i]=y[i]*x[i]
			end
			return unpack(z)
		end
end

--Returns a function that replaces with x
function replace(x)
	return function() return x end
end

--Returns a function that appends x
function append(x)
	return function(y) return y..x end
end

--Remove listed tags from the given text
local function line_exclude(text, exclude)
	remove_t=false
	local new_text=text:gsub("\\([^\\{}]*)",
		function(a)
			if a:find("^r")~=nil then
				for i,val in ipairs(exclude) do
					if val=="r" then return "" end
				end
			elseif a:find("^fn")~=nil then
				for i,val in ipairs(exclude) do
					if val=="fn" then return "" end
				end
			else
				_,_,tag=a:find("^([1-4]?%a+)")
				for i,val in ipairs(exclude) do
					if val==tag then
						--Hacky exception handling for \t statements
						if val=="t" then
							remove_t=true
							return "\\"..a
						end
						if a:match("%)$")~=nil then
							if a:match("$b()")~=nil then
								return ""
							else
								return ")"
							end
						end
						return ""
					end
				end
			end
			return "\\"..a
		end)
	if remove_t then
		new_text=new_text:gsub("\\t%b()","")
	end
	return new_text
end

--Returns the position of a line
local function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			_,_,align_n=line.text:find("\\an([%d%.%-]*)")
			if align_n==nil then
				_,_,align_dumb=line.text:find("\\a([%d%.%-]*)")
				if align_dumb==nil then
					--If the line has no alignment tags
					posx=line.x
					posy=line.y
				else
					--If the line has the \a alignment tag
					vid_x,vid_y=aegisub.video_size()
					align_dumb=tonumber(align_dumb)
					if align_dumb>8 then
						posy=vid_y/2
					elseif align_dumb>4 then
						posy=line.eff_margin_t
					else
						posy=vid_y-line.eff_margin_b
					end
					_temp=align_dumb%4
					if _temp==1 then
						posx=line.eff_margin_l
					elseif _temp==2 then
						posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
					else
						posx=vid_x-line.eff_margin_r
					end
				end
			else
				--If the line has the \an alignment tag
				vid_x,vid_y=aegisub.video_size()
				align_n=tonumber(align_n)
				_temp=align_n%3
				if align_n>6 then
					posy=line.eff_margin_t
				elseif align_n>3 then
					posy=vid_y/2
				else
					posy=vid_y-line.eff_margin_b
				end
				if _temp==1 then
					posx=line.eff_margin_l
				elseif _temp==2 then
					posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
				else
					posx=vid_x-line.eff_margin_r
				end
			end
		end
	end
	return posx,posy
end

--Returns the origin of a line
local function get_org(line)
	local _,_,orgx,orgy=line.text:find("\\org%(([%d%.%-]*),([%d%.%-]*)%)")
	if orgx==nil then
		return get_pos(line)
	end
	return orgx,orgy
end

--Returns a table of default values
local function style_lookup(line)
	local style_table={
		["alpha"] = "&H00&",
		["1a"] = alpha_from_style(line.styleref.color1),
		["2a"] = alpha_from_style(line.styleref.color2),
		["3a"] = alpha_from_style(line.styleref.color3),
		["4a"] = alpha_from_style(line.styleref.color4),
		["c"] = color_from_style(line.styleref.color1),
		["1c"] = color_from_style(line.styleref.color1),
		["2c"] = color_from_style(line.styleref.color2),
		["3c"] = color_from_style(line.styleref.color3),
		["4c"] = color_from_style(line.styleref.color4),
		["fscx"] = line.styleref.scale_x,
		["fscy"] = line.styleref.scale_y,
		["frz"] = line.styleref.angle,
		["frx"] = 0,
		["fry"] = 0,
		["shad"] = line.styleref.shadow,
		["bord"] = line.styleref.outline,
		["fsp"] = line.styleref.spacing,
		["fs"] = line.styleref.fontsize,
		["fax"] = 0,
		["fay"] = 0,
		["xbord"] =  line.styleref.outline,
		["ybord"] = line.styleref.outline,
		["xshad"] = line.styleref.shadow,
		["yshad"] = line.styleref.shadow,
		["blur"] = 0,
		["be"] = 0
	}
	return style_table
end

function lua_interpret(sub,sel)
	
	meta,styles=karaskel.collect_head(sub,false)
	
	--Show GUI
	pressed,results=aegisub.dialog.display(dialog_conf,{"Run","Cancel"})
	
	if pressed=="Cancel" then aegisub.cancel() end
	
	command=results["code"]
	
	new_sel={}
	
	--Run for all lines in selection
	i=1
	flags={}
	while i<=#sel and #sel<=1000 do
		li=sel[i]
		line=sub[li]
		
		aegisub.progress.set(100*i/#sel)
		
		karaskel.preproc_line(sub,meta,styles,line)
		
		--Break the line into a table
		local line_table={}
		if line.text:match("^{")==nil then
			line.text="{}"..line.text
		end
		line.text=line.text:gsub("}","}\t")
		j=1
		for thistag,thistext in line.text:gmatch("({[^{}]*})([^{}]*)") do
			line_table[j]={tag=thistag:gsub("\\1c","\\c"),text=thistext:gsub("^\t","")}
			j=j+1
		end
		line.text=line.text:gsub("}\t","}")
		
		--These functions are run at the end, at most once per line
		tasklist={}
		
		--Function to select line
		function _select()
			table.insert(tasklist,function()
					table.insert(new_sel,li)
					selected=true
				end)
		end
		
		--Function to duplicate line
		function _duplicate()
			table.insert(tasklist,1,function()
					table.insert(sel,i+1,li+1)
					sub.insert(li+1,table.copy(line))
					for _x=i+2,#sel do
						sel[_x]=sel[_x]+1
					end
					if #new_sel>0 then
						for _x,_ in ipairs(new_sel) do
							if new_sel[_x]>li+1 then
								new_sel[_x]=new_sel[_x]+1
							end
						end
					end
					duplicated=true
					flags["duplicate"]=true
				end)
		end
		
		--Function to modify line properties
		function _modify_line(prop,func)
			table.insert(tasklist,function()
					line[prop]=func(line[prop])
				end)
		end
		
		--Create state table
		state_table={}
		for j,a in ipairs(line_table) do
			state_table[j]={}
			for b in a.tag:gmatch("(\\[^\\}]*)") do
				if b:match("\\fs%d")~=nil then
					state_table[j]["fs"]=b:match("\\fs([%d%.]+)")
					state_table[j]["fs"]=tonumber(state_table[j]["fs"])
				elseif b:match("\\fn")~=nil then
					state_table[j]["fn"]=b:match("\\fn([^\\}]*)")
				elseif b:match("\\r")~=nil then
					state_table[j]["r"]=b:match("\\r([^\\}]*)")
				else
					_tag,_param=b:match("\\([1-4]?%a+)(%A[^\\}]*)")
					state_table[j][_tag]=tonumber(_param) or _param
				end
			end
		end
		
		--Create default state
		state=style_lookup(line)
			
		--Define position and origin objects
		pos={}
		org={}
		pos.x,pos.y=get_pos(line)
		org.x,org.y=get_org(line)
		
		--Now cycle through all tag-text pairs
		for j,a in ipairs(line_table) do
		
			--Wrappers for the once-per-line functions
			function duplicate() if j==1 then _duplicate() end end
			function select() if j==1 then _select() end end
			function modify_line(prop,func) if j==1 then _modify_line(prop,func) end end
			
			--Define variables
			text=a.text
			tag=a.tag
			
			--Update state
			for _tag,_param in pairs(state_table[j]) do
				state[_tag]=_param
			end
			
			--Get the parameter of the given tag
			function get(b)
				_param=tostring(state[b])
				if _param:match("%b()")~=nil then
					c={}
					for d in _param:gmatch("[^%(%),]+") do
						table.insert(c,d)
					end
					return unpack(c)
				end
				return _param
			end
			
			--Modify the given tag
			function modify(b,func)
				c={get(b)}
				if #c==1 then c=c[1] end
				d=""
				if type(c)=="table" then
					e={func(unpack(c))}
					d="("
					h="("
					f=""
					for _i,g in ipairs(e) do
						d=d..f..g
						h=h..f..c[_i]
						f=","
					end
					d=d..")"
					c=h..")"
				else
					d=func(c)
					if tonumber(d)~=nil then
						d=float2str(tonumber(d))
					end
				end
				tag,_num=tag:gsub("\\"..b..esc(c),"\\"..b..esc(d))
				if _num<1 then insert("\\"..b..esc(d)) end
			end
			
			--Remove the given tags
			function remove(...)
				b=arg
				tag=line_exclude(tag,b)
			end
			
			--Insert the given tag at the end
			function insert(b)
				tag=tag:gsub("}$",b.."}")
			end
			
			--Run the user's code
			_com,err=loadstring(command)
			_com()
			
			if err then aegisub.log(err) aegisub.cancel() end
			
			a.text=text
			a.tag=tag
		end
		
		for _,task in ipairs(tasklist) do
			task()
		end
		
		--Rebuild
		rebuilt_text=""
		for _,a in ipairs(line_table) do
			rebuilt_text=rebuilt_text..a.tag..a.text
		end
		line.text=rebuilt_text:gsub("{}","")
		
		--Reinsert
		sub[li]=line
		
		--Increment
		i=i+1
	end
	
	aegisub.set_undo_point(script_name)
	
	--Return new selection or old selection
	if #new_sel>0 then return new_sel end
	return sel
	
end


aegisub.register_macro(script_name,script_description,lua_interpret)