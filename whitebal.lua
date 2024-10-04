--[[
@title WHITE BALANCE RAW
@chdk_version 1.4.0.4193
#white_balance=true "White balance"
#shots=3 "Shots" -- configurable parameter
#illuminant=s_D65 "RGB_Illuminant" {Adobe_D65 Apple_D65 CIE_E ColorMatch_D50 ECI_D50 Ekta_D50 ProPhoto_D50 s_D65 SMPTEC_D65} table
#remove_gamma=false "Remove gamma"
#meter_size_x=500 "Meter width X"  [20 999]
#meter_size_y=400 "Meter height Y" [20 999]
#enable_raw=false "Enable raw"
#calibrate=false "Calibrate"
#calib_r=500 "Calib Red"   [0 999]
#calib_g=500 "Calib Green" [0 999]
#calib_b=500 "Calib Blue"  [0 999]
]]

-- #shots=1 "Shots" -- configurable parameter
-- shots=1 -- always 1 shot

require'hookutil'
require'rawoplib'
props=require'propcase'

function printf(fmt,...)
	print(string.format(fmt,...))
end

-- **** begin fixed point formatter ****
-- Int2Str function is obsolete
-- fixed point integer to string formatter
-- Int2Str(value[,x10^dpow:default=0[, unit:string][, fix:number]])
function Int2Str(val, dpow, ...)
    local _dpow, _sign, _val, _unit, _fix = dpow or 0, (val < 0) and "-" or "", tostring(math.abs(val))
    for i = 1, select('#', ...) do
        local _arg = select(i, ...)
        if not _unit and type(_arg) == "string" and #_arg > 0 then _unit = _arg
        elseif not _fix and type(_arg) == "number" and _arg >= 0 then _fix = _arg
        end
    end
    _val = (_dpow < 0) and string.rep("0", 1 - #_val - _dpow) .. _val or _val .. string.rep("0", _dpow)
    local _int, _frac = string.match(_val, "^([%d]+)(" .. string.rep("%d", -_dpow) .. ")$")
    _frac = _fix and string.sub((_frac or "") .. string.rep("0", _fix), 1, _fix) or _frac
    _frac = (_frac and type(_frac) == "string" and #_frac > 0) and "." .. _frac or ""
    return  string.format("%s%s%s%s", _sign, _int, _frac, _unit or "")
end

-- max_size = 6 right-aligns 123 to " 1.230"
function str1E3(val,max_size)
  s = fmath.new(val,1000):tostr(3)
  return string.rep(" ",(max_size or 0)-string.len(s)) .. s
end
-- **** end fixed point formatter ****


-- **** begin 7-segment display ****
--
--    aaaa
--   f    b
--   f    b
--    gggg
--   e    c
--   e    c
--    dddd  .
--
digit2seg7 = {
    ["-"]="g",
    ["0"]="abcdef",
    ["1"]="bc",
    ["2"]="abged",
    ["3"]="abgcd",
    ["4"]="fgbc",
    ["5"]="afgcd",
    ["6"]="afgedc",
    ["7"]="abc",
    ["8"]="abcdefg",
    ["9"]="abcdfg",
    ["."]=".",
    ["A"]="efabcg",
    ["R"]="afe",
    ["G"]="abcfg",
    ["B"]="fedcg",
    ["X"]="fbgec",
    ["Y"]="fbgdc",
    ["Z"]="abged",
    ["="]="gd",
    [" "]="",
    }
    
  -- segment lines (x1,y1 - x2,y2) coordinates
  -- only vertical or horizontal lines
  -- supported by graphics using fill_rect
seg7_line = {
    ["a"]={ 1, 0,   4, 0},
    ["b"]={ 5, 1,   5, 4},
    ["c"]={ 5, 6,   5, 9},
    ["d"]={ 1,10,   4,10},
    ["e"]={ 0, 6,   0, 9},
    ["f"]={ 0, 1,   0, 4},
    ["g"]={ 1, 5,   4, 5},
    ["."]={ 2, 8,   2,10},
  }

-- x,y - coordinate of upper left corner
-- d digits string containing "0"-"9", "."
-- w digit width
-- h digit height
-- p pitch (digit to digit distance)
-- t digit thickness
-- r,g,b rgb values (raw sensor rgb space)
function draw_digits(x,y,d,w,h,p,t,r,g,b) -- 7-segment display
  for i = 1, #d do
    local l = digit2seg7[d:sub(i,i)]
    local x1,y1,x2,y2
    for j = 1, #l do
      local s = seg7_line[l:sub(j,j)]
      x1 =  x + (i-1)*p + s[1]*w/5
      y1 =  y + s[2]*h/10
      x2 =  x + (i-1)*p + s[3]*w/5
      y2 =  y + s[4]*h/10
      if y1 == y2 then -- horizontal line
	rawop.fill_rect_rgbg(x1-t/2, y1-t/2, x2-x1+t, t, r, g, b, g)
      end
      if x1 == x2 then -- vertical line
	rawop.fill_rect_rgbg(x1-t/2, y1-t/2, t, y2-y1+t, r, g, b, g)
      end
    end
  end
end -- 7-segment display
-- **** end 7-segment display ****


-- ******** begin color space conversion *********
-- conversion matrix
-- various colorspaces and illuminators
-- from http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
RGB2XYZ1E7 =
{
  ["Adobe_D65"] = -- Adobe RGB (1998), D65
  {
    {5767309,  1855540,  1881852},
    {2973769,  6273491,   752741},
    { 270343,   706872,  9911085},
  },
  ["Apple_D65"] = -- Apple RGB, D65
  {
    {4497288,  3162486,  1844926},
    {2446525,  6720283,   833192},
    { 251848,  1411824,  9224628},
  },
  ["CIE_E"] = -- CIE RGB, E
  {
    {4887180,  3106803,  2006017},
    {1762044,  8129847,   108109},
    {      0,   102048,  9897952},
  },
  ["ColorMatch_D50"] = -- ColorMatch RGB, D50
  {
    {5093439,  3209071,  1339691},
    {2748840,  6581315,   669845},
    { 242545,  1087821,  6921735},
  },
  ["ECI_D50"] = -- ECI RGB, D50
  {
    {6502043,  1780774,  1359384},
    {3202499,  6020711,   776791},
    {      0,   678390,  7573710},
  },
  ["Ekta_D50"] = -- EktaSpace PS5, D50
  {
    {5938914,  2729801,   973485},
    {2606286,  7349465,    44249},
    {      0,   419969,  7832131},
  },
  ["ProPhoto_D50"] = -- ProPhoto, D50
  {
    {7976749,  1351917,   313534},
    {2880402,  7118741,      857},
    {      0,        0,  8252100},
  },
  ["s_D65"] = -- sRGB, D65
  {
    {4124564,  3575761,  1804375},
    {2126729,  7151522,   721750},
    { 193339,  1191920,  9503041},
  },
  ["SMPTEC_D65"] = -- SMPTE-C, D65
  {
    {3935891,  3652497,  1916313},
    {2124132,  7010437,   865432},
    { 187423,  1119313,  9581563},
  },
}


-- inverse gamma
-- in JPEGs RGB values 0-255 have
-- already applied gamma function which
-- this function removes and returns linear RGB
-- input  gamma RGB (0-100) (0-255 must be scaled to 0-100)
-- output linear RGB (0-100)
-- all values in imath.scale
-- imath 0-100 are integers 0-100000
function igama(var)
  local gama_thresh =  4045 --  0.04045 * 100 * 1000
  local gama_add    =  5500 --  0.05500 * 100 * 1000
  local gama_pow    =  2400 --  2.400 * 1000
  local gama_mul    =    65 --  6.458/100 * 1000 = 100^(1/2.4) / (1.055*100) * 1000
  local gama_div    = 12920 -- 12.920 * 1000

  if var > gama_thresh then
    var = imath.pow( imath.mul(var + gama_add, gama_mul), gama_pow)
  else
    var = imath.div(var, gama_div)
  end

  return var
end

-- colorspace conversion formula
-- input RGB imath 0-100
-- output XYZ imath 0-100
-- imath 0-100 are integers 0-100000
function rgb2xyz(var_R, var_G, var_B)
  -- un-gamma RGB ?
  -- it depends on image sensors
  if remove_gamma then
    var_R = igama(var_R)
    var_G = igama(var_G)
    var_B = igama(var_B)
  end

  -- conversion matrix
  -- see http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  -- depends on standard viewpoint and light source
  -- Observer = 2°, Illuminant = D65
  -- local space_illum = "s_D65"
  local space_illum = illuminant[illuminant.index]
  local xr = RGB2XYZ1E7[space_illum][1][1] / 10000
  local xg = RGB2XYZ1E7[space_illum][1][2] / 10000
  local xb = RGB2XYZ1E7[space_illum][1][3] / 10000
  local yr = RGB2XYZ1E7[space_illum][2][1] / 10000
  local yg = RGB2XYZ1E7[space_illum][2][2] / 10000
  local yb = RGB2XYZ1E7[space_illum][2][3] / 10000
  local zr = RGB2XYZ1E7[space_illum][3][1] / 10000
  local zg = RGB2XYZ1E7[space_illum][3][2] / 10000
  local zb = RGB2XYZ1E7[space_illum][3][3] / 10000

  -- RGB to XYZ conversion (matrix dot-product)
  -- [X]   [xr xg xb]   [R]
  -- [Y] = [yr yg yb] . [G]
  -- [Z]   [zr zg zb]   [B]
  local X = imath.mul(var_R, xr) + imath.mul(var_G, xg) + imath.mul(var_B, xb)
  local Y = imath.mul(var_R, yr) + imath.mul(var_G, yg) + imath.mul(var_B, yb)
  local Z = imath.mul(var_R, zr) + imath.mul(var_G, zg) + imath.mul(var_B, zb)

  return X,Y,Z
end
-- ******** end color space conversion *********


-- ********* white balance interpolation ********
-- initialize RGB calibration matrix
-- but for now we start from non-modifying RGB
-- later, it should be read from a file
-- those numbers are raw sensor values obtained
-- by taking 3 shots of various exposition
-- of referent white color surface
cal_rgb =
{
  { 99999, 99999, 99999 }, -- exposition 1/x
  { 49999, 49999, 49999 }, -- exposition 1/2x
  {     0,     0,     0 }, -- exposition 1/4x
}

-- convert input R,G,B (0-99999)
-- to balanced values
-- using parabolic 3-point interpolation
-- uses cal_rgb global variable
function balance(R, G, B) -- R,G,B from 0 to 99999
  -- base channel is the one with maximum
  -- raw value. it will be linearized 0-99999
  -- other channels will follow the base
  -- todo: find max value, currently we fix it to green
  local base_chan = 2
  -- simplistic approach: linear interpolation
  -- make all sensors be the same as green
  local target_rgb = {{},{},{}}
  for i=1,3 do
    for j=1,3 do
      target_rgb[i][j]=cal_rgb[i][base_chan]
    end
  end

  -- linear interpolate non-basse chan to base chan
  -- linear a*x+b
  local a = {}
  local b = {}
  for j=1,3 do
    -- math.floor()
    a[j] = imath.div((target_rgb[1][base_chan]-target_rgb[3][base_chan]), (cal_rgb[1][j]-cal_rgb[3][j]))
    b[j] = target_rgb[3][j] - imath.mul(cal_rgb[3][j], a[j])
  end

  R = imath.mul(R, a[1]) + b[1]
  G = imath.mul(G, a[2]) + b[2]
  B = imath.mul(B, a[3]) + b[3]

  return R,G,B
end

function write_cal_file()
  local calfile=io.open("A/colorcal.txt","wb")
  for i=1,3 do
    for j=1,3 do
      calfile:write(string.format("%d\n", cal_rgb[i][j]))
    end
  end
  -- calfile:close()
end

function read_cal_file()
  local calfile=io.open("A/colorcal.txt","rb")
  for i=1,3 do
    for j=1,3 do
      cal_rgb[i][j] = calfile:read("*n")
    end
  end
  -- calfile:close()
end

-- ********* white balance interpolation ********


-- ******** begin image processing *********
function do_whitebalance()
	--logfile=io.open("A/colorspc.log","wb")
	--logfile:write(string.format("illuminant = >>%s<<\n", illuminant[illuminant.index]))
	--logfile:write(string.format("meter r=%d g1=%d g2=%d b=%d\n",r,g1,g2,b))
	--logfile:write(string.format("meter r=%s g1=%s g2=%s b=%s\n",str1E3(i_r),str1E3(i_g1),str1E3(i_g2),str1E3(i_b)))
	--logfile.close()

end -- do_whitebalance


-- function that will write to RAW image
-- graphics will be added to image by modifying
-- raw sensor data before compressing to jpeg
function do_colorspace(use_cal)
 	local min_level = rawop.get_black_level() + 1
 	local max_level = rawop.get_white_level() - 1

        -- centered 500 px square (from parameters)
	--local meter_size_x = 500
	--local meter_size_y = 400
	
	local font_h = 200         -- digit height Y
	local font_w = font_h/2    -- digit width X
	local font_p = font_h*3/4  -- pitch (column width) X
	local font_t = font_h/10   -- segment line thickness
	local font_nl = font_h*3/2  -- line (row width) Y

	local x1 = rawop.get_raw_width()/2 - meter_size_x/2
	local y1 = rawop.get_raw_height()/2 - meter_size_y/2

	-- local m = rawop.meter(x1,y1,meter_size_x,meter_size_y,1,1)
	local r,g1,b,g2 = rawop.meter_rgbg(x1,y1,meter_size_x/2,meter_size_y/2,2,2)

	-- draw white rectangle around metered area
	rawop.rect_rgbg(x1-2,y1-2,meter_size_x+4,meter_size_y+4,2,max_level,max_level,max_level)

	-- draw small coloured boxes at 4 corners of metered area
	rawop.fill_rect_rgbg(x1,y1,16,16,r,min_level,min_level)
	rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1,16,16,min_level,g1,min_level)
	rawop.fill_rect_rgbg(x1,y1 + meter_size_y - 16,16,16,min_level,g2,min_level)
	rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1 + meter_size_y - 16,16,16,min_level,min_level,b)
	
	-- below the metered area, reproduce the average color bar
	rawop.fill_rect_rgbg(x1,y1+meter_size_y+100,meter_size_x,200,r,g1,b,g2)

        -- fixed point arithmetic
        -- imath.mul(a,b), imath.div(a,b)
        -- imath.sqrt(a),
        -- imath.sinr(a), imath.cosr(a) -- radians sine
        -- for more examples see imath.lua
        local i_scale, i_r, i_g1, i_g2, i_g, i_b
	i_scale = imath.scale
	i_r  = (r-min_level)  * i_scale
	i_g1 = (g1-min_level) * i_scale
	i_g2 = (g2-min_level) * i_scale
	i_g  = (i_g1+i_g2)/2
	i_b  = (b-min_level)  * i_scale

	local i_range = (max_level-min_level) * (i_scale / 100)
	i_r = imath.div(i_r, i_range)
	i_g = imath.div(i_g, i_range)
	i_b = imath.div(i_b, i_range)
	
	if use_cal then
	  i_r, i_g, i_b = balance(i_r, i_g, i_b)
	end

	-- draw RGB (color) digits right aligned on the left side
	local x_left = rawop.get_jpeg_left()+400
	draw_digits(x_left,y1+font_nl*0,str1E3(i_r,6),font_w,font_h,font_p,font_t, max_level, min_level, min_level)
	draw_digits(x_left,y1+font_nl*1,str1E3(i_g,6),font_w,font_h,font_p,font_t, min_level, max_level, min_level)
	draw_digits(x_left,y1+font_nl*2,str1E3(i_b,6),font_w,font_h,font_p,font_t, min_level, min_level, max_level)

	local i_X,i_Y,i_Z
	i_X,i_Y,i_Z = rgb2xyz(i_r, i_g, i_b)
	local i_x,i_y
	i_x = imath.div(i_X, i_X+i_Y+i_Z)
	i_y = imath.div(i_Y, i_X+i_Y+i_Z)

	-- draw XY (white) digits left aligned on the right side
	draw_digits(x1+meter_size_x+100,y1+font_nl*0,str1E3(i_x),font_w,font_h,font_p,font_t, max_level, max_level, max_level)
	draw_digits(x1+meter_size_x+100,y1+font_nl*1,str1E3(i_y),font_w,font_h,font_p,font_t, max_level, max_level, max_level)

	-- printf("meter r=%d g1=%d g2=%d b=%d",r,g1,g2,b)
	--logfile=io.open("A/colorspc.log","wb")
	--logfile:write(string.format("illuminant = >>%s<<\n", illuminant[illuminant.index]))
	--logfile:write(string.format("meter r=%d g1=%d g2=%d b=%d\n",r,g1,g2,b))
	--logfile:write(string.format("meter r=%s g1=%s g2=%s b=%s\n",str1E3(i_r),str1E3(i_g1),str1E3(i_g2),str1E3(i_b)))
	--logfile.close()
	return i_r, i_g, i_b
end -- do_colorspace
-- ******** begin image processing *********

-- ******** begin shooting logic *********
-- for ptp file exec
if not shots then 
	shots = 1
end


prev_raw_conf=get_raw()
if enable_raw then
	set_raw(true)
end


if white_balance then
  --shoot();
  press('shoot_half')
  repeat sleep(10) until get_shooting()
  afl_av=get_av96()
  afl_sv=get_sv96()
  afl_tv=get_tv96()
  release('shoot_half')
  -- set_aflock(1) -- focus lock - no more change of the focus

  cal_rgb={{},{},{}} -- we will get here bracketed values
  for i=1,3 do -- 3 shots for bracketing
        shoot() -- fix this more elegant way
        -- without shoot() tv value is set for the first time
        -- but subsequent shots with hooks will ignore it
        -- must be a better way to do bracketing with raw hooks
        -- tv96 -- exposure time, logarithmic
        -- when adding 48 then exposition time 2 times shorter (faster)
        -- and picture is dimmer
        set_tv96_direct(afl_tv+((i-1)*48))
        set_sv96(afl_sv)
        set_av96(afl_av)
        
        -- sleep(200)
        -- set hook in raw for drawing
        hook_raw.set(10000)
        press('shoot_half')
        repeat sleep(10) until get_shooting()
        -- sleep(200)
        press('shoot_full_only')

	-- wait for the image to be captured
	hook_raw.wait_ready()

	local count, ms = set_yield(-1,-1)
	-- get sensor values
        cal_rgb[i][1], cal_rgb[i][2], cal_rgb[i][3] = do_colorspace(false)
	set_yield(count, ms)

	hook_raw.continue()
	release('shoot_full_only')
	release('shoot_half')
	hook_raw.set(0)
	-- set_aflock(0)
	-- sleep(1900)
  end -- for shots
  -- now we have all the sensor values ready in cal_rgb[1..3][1..3]
  -- cal_rgb[number_of_shots][1-red, 2-green, 3-blue]
  -- we can interpolate them for a white balance
  R,G,B = balance(cal_rgb[1][1], cal_rgb[1][2], cal_rgb[1][3])
  -- write calib data to file
  write_cal_file()
else -- not white balance (normal operation)
  read_cal_file()
  for i=1,shots do -- 3 shots for bracketing
        -- sleep(200)
        -- set hook in raw for drawing
        hook_raw.set(10000)
        press('shoot_half')
        repeat sleep(10) until get_shooting()
        -- sleep(200)
        press('shoot_full_only')

	-- wait for the image to be captured
	hook_raw.wait_ready()

	local count, ms = set_yield(-1,-1)
	-- get sensor values
        TR, TG, TB = do_colorspace(true)
	set_yield(count, ms)

	hook_raw.continue()
	release('shoot_full_only')
	release('shoot_half')
	hook_raw.set(0)
	-- set_aflock(0)
	-- sleep(1900)
  end -- for shots
end -- white balance

if enable_raw then
	set_raw(prev_raw_conf)
end

if white_balance then
  set_tv96(afl_tv)
  set_sv96(afl_sv)
  set_av96(afl_av)
  set_aflock(0)
end

sleep(200)

--logfile=io.open("A/colorspc.log","wb")
--for i=1,3 do
--  logfile:write(string.format("wb %d r=%s g=%s b=%s\n", i, str1E3(cal_rgb[i][1]), str1E3(cal_rgb[i][2]), str1E3(cal_rgb[i][2]) ))
--end
--logfile:write(string.format("test r=%s g=%s b=%s\n", str1E3(R), str1E3(G), str1E3(B) ))
--logfile:close()

--print("press any key for end")
--wait_click(0)
--cls()
-- ******** end shooting logic *********
