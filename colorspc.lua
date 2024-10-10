--[[
@title COLOR SPACE RGB->xyY (CIE)
@chdk_version 1.6
#calibrate=false "Calibrate"
#calib_point=1 "Calib point" [1 3]
#calib_target=xyY "Calib target" {Gardner xyY} table
#gardner=11 "Calib Gardner" [1 18]
#calib_x=333 "Calib x"  [0 999]
#calib_y=333 "Calib y"  [0 999]
#calib_Y=333 "Calib Y"  [0 999]
#over_XYZ=true "Over XYZ"
#meter_size_x=500 "Meter width X"  [20 999]
#meter_size_y=400 "Meter height Y" [20 999]
#font_h=200 "Font height" [10 1000]
#wait_for_key=false "Wait for a key"
#enable_raw=false "Enable raw"
]]

-- for known camera it is recommended to
-- hardcode illuminant and inverse_gamma
-- to avoid misconfiguration
-- SX280HS
-- illuminant="CIE_E"
-- inverse_gamma="None"

shots=1 -- hardcode always 1 shot

-- white is CIE x=0.333 y=0.333

require'hookutil'
require'rawoplib'
props=require'propcase'

function printf(fmt,...)
	print(string.format(fmt,...))
end

-- **** begin float formatter ****
-- max_size = 6 right-aligns 1.23 to " 1.230"
function str1E3(val,max_size)
  s = val:tostr(3)
  return string.rep(" ",(max_size or 0)-#s) .. s
end

function printvec3(v)
  print(str1E3(v[1],7) .. str1E3(v[2],7) .. str1E3(v[3],7))
end

-- print 3x3 float matrix
function printmat3x3(m)
  for i = 1,3 do
    printvec3(m[i])
  end
end

-- **** end float formatter ****


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
    ["B"]="fedcg",
    ["C"]="adef",
    ["G"]="abcfg",
    ["L"]="def",
    ["R"]="afe",
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

-- **** begin color reference tables ***
-- gardner is standard for shades of yellow
-- https://www.shimadzu.com/an/sites/shimadzu.com.an/files/pim/pim_document_file/applications/application_note/13384/sia116002.pdf
-- https://www.kelid1.ir/FilesUp/ASTM_STANDARS_971222/D6166.PDF
-- Y values from above table are considered as % brightness
-- in our table Y is scaled to 0-1
GARDNER2XY1E4 =
{ --  x    y    Y *1E4
  {3177,3303,8000}, -- 1
  {3233,3352,7900}, -- 2
  {3329,3452,7600}, -- 3
  {3437,3644,7500}, -- 4
  {3558,3840,7400}, -- 5
  {3767,4061,7100}, -- 6
  {4044,4352,6700}, -- 7
  {4207,4498,6400}, -- 8
  {4343,4640,6100}, -- 9
  {4503,4760,5700}, -- 10
  {4842,4818,4500}, -- 11
  {5077,4638,3600}, -- 12
  {5392,4458,3000}, -- 13
  {5646,4270,2200}, -- 14
  {5857,4089,1600}, -- 15
  {6047,3921,1100}, -- 16
  {6290,3701, 600}, -- 17
  {6477,3521, 400}, -- 18
}
-- **** end color reference tables ***

-- computes the inverse of a matrix m
-- input float matrix 3x3
-- output inverse float matrix 3x3
function matinv3x3(m)
  -- inverse determinant
  local invdet = fmath.new(1,1) /
         ( m[1][1] * (m[2][2] * m[3][3] - m[3][2] * m[2][3]) -
           m[1][2] * (m[2][1] * m[3][3] - m[2][3] * m[3][1]) +
           m[1][3] * (m[2][1] * m[3][2] - m[2][2] * m[3][1]) )

  local minv = {{},{},{}} -- placeholder array for inverse of matrix m
  minv[1][1] = (m[2][2] * m[3][3] - m[3][2] * m[2][3]) * invdet;
  minv[1][2] = (m[1][3] * m[3][2] - m[1][2] * m[3][3]) * invdet;
  minv[1][3] = (m[1][2] * m[2][3] - m[1][3] * m[2][2]) * invdet;
  minv[2][1] = (m[2][3] * m[3][1] - m[2][1] * m[3][3]) * invdet;
  minv[2][2] = (m[1][1] * m[3][3] - m[1][3] * m[3][1]) * invdet;
  minv[2][3] = (m[2][1] * m[1][3] - m[1][1] * m[2][3]) * invdet;
  minv[3][1] = (m[2][1] * m[3][2] - m[3][1] * m[2][2]) * invdet;
  minv[3][2] = (m[3][1] * m[1][2] - m[1][1] * m[3][2]) * invdet;
  minv[3][3] = (m[1][1] * m[2][2] - m[2][1] * m[1][2]) * invdet;

  return minv
end

-- test matrix inversion
--  input
-- [2 1 3]
-- [0 2 4]
-- [1 1 2]
--  output
-- [ 0 -0.5  1]
-- [-2 -0.5  4]
-- [ 1  0.5 -2]
-- verified with maxima
-- a: matrix([2,1,3],[0,2,4],[1,1,2]);
-- invert(a);
function test_matinv3x3()
  local imat = {{2,1,3},
                {0,2,4},
                {1,1,2}}
  -- convert int to float
  local fmat = mat3x3int2float(imat,1)
  print("input matrix")
  printmat3x3(fmat)
  print("inverted matrix")
  printmat3x3(matinv3x3(fmat))
end

-- input matrix 3x3, vector 3
-- output vector 3
-- p = m . v
function dotproduct(m,v)
  local p = {}
  for i=1,3 do
    p[i] = m[i][1]*v[1] + m[i][2]*v[2] + m[i][3]*v[3]
  end
  return p
end

-- input matrix 3x3, matrix 3x3
-- output matrix 3x3
-- p = a . b
function dot3x3(a,b)
  local p = {{},{},{}}
  for i=1,3 do
    for j=1,3 do
      p[i][j] = a[i][1]*b[1][j] + a[i][2]*b[2][j] + a[i][3]*b[3][j]
    end
  end
  return p
end

-- verify with maxima
-- a:matrix([2,1,3],[0,2,4],[1,1,2]);
-- b:matrix([1,4,1],[2,4,1],[2,1,3]);
-- a . b;
-- maxima -b examples/dotproduct.maxima
-- [ 10  15  12 ]
-- [ 12  12  14 ]
-- [ 7   10  8  ]
function test_dot3x3()
  local ia   = {{2,1,3},
                {0,2,4},
                {1,1,2}}
  local ib   = {{1,4,1},
                {2,4,1},
                {2,1,3}}
  local a = mat3x3int2float(ia,1)
  print("input matrix a")
  printmat3x3(a)
  local b = mat3x3int2float(ib,1)
  print("input matrix b")
  printmat3x3(b)
  print("dot product a . b")
  printmat3x3(dot3x3(a,b))
end

function transpose3x3(a)
  local b = {{},{},{}}
  for i=1,3 do
    for j=1,3 do
      b[i][j] = a[j][i]
    end
  end
  return b
end

-- input values from sensor RGB =
-- [R1 G1 B1]
-- [R2 G2 B2]
-- [R3 G3 B3]
-- input calibration targets XYZ =
-- [X1 Y1 Z1]
-- [X2 Y2 Z2]
-- [X3 Y3 Z3]
-- output conversion matrix RGB->XYZ
function solve_RGB2XYZ(RGB,XYZ)
  return transpose3x3(dot3x3(matinv3x3(RGB),XYZ))
end

-- verify with maxima
-- a:matrix([1,2,-1],[3,1,2],[2,2,1]);
-- b:matrix([1,2,3],[3,2,-1],[1,3,4]);
-- xt:transpose(expand(invert(a) . b));
-- maxima -b examples/matrix_lin_eq.maxima
-- [  2   -1   -1   ]
-- [ -0.2  1.4  0.6 ]
-- [ -3    4    2   ]
function test_RGB2XYZ()
  local ia   = {{1,2,-1},
                {3,1,2},
                {2,2,1}}
  local ib   = {{1,2,3},
                {3,2,-1},
                {1,3,4}}
  local a = mat3x3int2float(ia,1)
  print("input matrix RGB")
  printmat3x3(a)
  local b = mat3x3int2float(ib,1)
  print("input matrix XYZ")
  printmat3x3(b)
  print("transform RGB->XYZ")
  printmat3x3(solve_RGB2XYZ(a,b))
end

-- return im/scale
function mat3x3int2float(im,scale)
  local m = {{},{},{}}
  for i = 1,3 do
    for j = 1,3 do
      m[i][j] = fmath.new(im[i][j],scale)
    end
  end
  return m
end
-- ******** end color space conversion *********


-- ******** begin image processing *********
-- colorimetry calculation
-- temporary display on screen
-- markings on saved picture
-- TODO if use_cal==true then apply calibration using CALRGB1E6
function calculate_colorspace()
  -- local font_h  = 200        -- digit height Y taken from script arguments
  local font_w  = font_h/2   -- digit width X
  local font_p  = font_h*3/4 -- pitch (column width) X
  local font_t  = font_h/10  -- segment line thickness
  local font_nl = font_h*3/2 -- line (row width) Y

  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095

  -- centered 500 px square (from parameters)
  --local meter_size_x = 500
  --local meter_size_y = 400

  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2

  -- int rgb to float rgb range 0-1
  local r,g,b = measure_rgb(true)

  -- apply calibration
  local CIE_x,CIE_y,CIE_Y = apply_cal_RGB2xyY(r,g,b)

  -- stamp RGB (color) digits right aligned on the left side
  -- stamp xyY (white) digits left aligned on the right side
  stamp_numbers(r,g,b,CIE_x,CIE_y,CIE_Y)

  set_console_layout(0,0,40,12)
  --printf("meter r=%d g1=%d g2=%d b=%d",r,g1,g2,b)
  --printf("gardner %d: x=0.%d y=0.%d", gardner, GARDNER2XY1E4[gardner][1], GARDNER2XY1E4[gardner][2] )
  --printf("black=%d white=%d", min_level, max_level)
  printf("R=%s G=%s B=%s",str1E3(r,6),str1E3(g,6),str1E3(b,6))
  printf("x=%s y=%s Y=%s (CIE)",str1E3(CIE_x,6),str1E3(CIE_y,6),str1E3(CIE_Y,6))
  --logfile=io.open("A/colorspc.log","wb")
  --logfile.close()
  return r,g,b
end -- do_colorspace
-- ******** begin image processing *********

-- **** begin calibration ****
-- white balance or reference color with known
-- CIE xy value

-- initialize RGB calibration matrix
-- but for now we start from non-modifying RGB
-- later, it should be read from a file
-- those numbers are raw sensor values obtained
-- by taking 3 shots of various exposition
-- of referent color surface
-- float's 0-1 are scaled as int's 0-1000000 (1E6)
CALRGB1E6 =
{
  { 999999, 999999, 999999 }, -- RGB point 1 exposition 1/x
  { 499999, 499999, 499999 }, -- RGB point 2 exposition 1/2x
  {      0,      0,      0 }, -- RGB point 3 exposition 1/4x
}

CALxyY1E6 =
{
  { 333333, 333333, 333333 }, -- xyY point 1
  { 333333, 333333, 333333 }, -- xyY point 2
  { 333333, 333333, 333333 }, -- xyY point 3
}

function write_rgb2xyy_file()
  local calfile=io.open("A/rgb2xyy.txt","wb")
  if calfile then
    for i=1,3 do
      for j=1,3 do
        calfile:write(string.format("%d ", CALRGB1E6[i][j]))
      end
      for j=1,3 do
        calfile:write(string.format("%d ", CALxyY1E6[i][j]))
      end
      calfile:write("\n")
    end
    calfile:close()
    return true
  end
  return false
end

function read_rgb2xyy_file()
  local calfile=io.open("A/rgb2xyy.txt","rb")
  if calfile then
    for i=1,3 do
      for j=1,3 do
        CALRGB1E6[i][j] = calfile:read("*n")
      end
      for j=1,3 do
        CALxyY1E6[i][j] = calfile:read("*n")
      end
    end
    calfile:close()
    return true
  end
  return false
end

-- stamp=true stamp measured area
-- stamp=false don't stamp only measure
-- return r,g,b floats
function measure_rgb(stamp)
  -- meter range
  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095

  local r,g1,b,g2 = meter_square(stamp)
  --print(string.format("r=%d g1=%d g2=%d b=%d",r,g1,g2,b))
  fr = fmath.new(  2*r-2*min_level,2*(max_level-min_level+1))
  fg = fmath.new(g1+g2-2*min_level,2*(max_level-min_level+1))
  fb = fmath.new(  2*b-2*min_level,2*(max_level-min_level+1))

  return fr,fg,fb
end

-- stamp=true stamp measured area
-- stamp=false don't stamp only measure
-- return r,g1,b,g2 int's
function meter_square(stamp)
  local line_t  = font_h/10  -- segment line thickness
  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095
  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2
  -- local m = rawop.meter(x1,y1,meter_size_x,meter_size_y,1,1)
  local r,g1,b,g2 = rawop.meter_rgbg(x1,y1,meter_size_x/2,meter_size_y/2,2,2)
  if stamp then
    -- stamp white rectangle around metered area
    -- line thickness same as font
    for i=1,line_t do
      rawop.rect_rgbg(x1-1-i,y1-1-i,meter_size_x+2+i+i,meter_size_y+2+i+i,2,max_level,max_level,max_level)
    end
    -- stamp small coloured boxes at 4 corners of metered area
    rawop.fill_rect_rgbg(x1,y1,16,16,r,min_level,min_level)
    rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1,16,16,min_level,g1,min_level)
    rawop.fill_rect_rgbg(x1,y1 + meter_size_y - 16,16,16,min_level,g2,min_level)
    rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1 + meter_size_y - 16,16,16,min_level,min_level,b)
    -- below the metered area, reproduce the average color bar
    rawop.fill_rect_rgbg(x1,y1+meter_size_y+meter_size_y/4,meter_size_x,meter_size_y/2,r,g1,b,g2)
  end
  return r,g1,b,g2
end

-- all inpot parameters are float's
-- stamped on raw picture
-- formatted like 0.000
function stamp_numbers(r,g,b,x,y,Y)
  -- local font_h  = 200        -- digit height Y taken from script arguments
  local font_w  = font_h/2   -- digit width X
  local font_p  = font_h*3/4 -- pitch (column width) X
  local font_t  = font_h/10  -- segment line thickness
  local font_nl = font_h*3/2 -- line (row width) Y

  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095

  -- centered 500 px square (from parameters)
  --local meter_size_x = 500
  --local meter_size_y = 400

  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2

  -- stamp RGB (color) digits right aligned on the left side
  -- local x_left = rawop.get_jpeg_left()+400
  local x_left = x1-font_p*7
  -- y_top centers digits in y axis
  local y_top  = (y1+meter_size_y/2)-font_nl*3/2+(font_nl-font_h)/2
  draw_digits(x_left,y_top+font_nl*0,str1E3(r,6),font_w,font_h,font_p,font_t, max_level, min_level, min_level)
  draw_digits(x_left,y_top+font_nl*1,str1E3(g,6),font_w,font_h,font_p,font_t, min_level, max_level, min_level)
  draw_digits(x_left,y_top+font_nl*2,str1E3(b,6),font_w,font_h,font_p,font_t, min_level, min_level, max_level)

  -- stamp xy (white) digits left aligned on the right side
  local x_right = x1+meter_size_x+font_p
  draw_digits(x_right,y_top+font_nl*0,str1E3(x),font_w,font_h,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right,y_top+font_nl*1,str1E3(y),font_w,font_h,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right,y_top+font_nl*2,str1E3(Y),font_w,font_h,font_p,font_t, max_level, max_level, max_level)

  -- font size calc for lowercase "xy" and uppercase "Y"
  draw_digits(x_right+font_p*11/2,y_top+font_nl*0+font_h/4,"X",font_w*3/4,font_h*3/4,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right+font_p*11/2,y_top+font_nl*1+font_h/4,"Y",font_w*3/4,font_h*3/4,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right+font_p*11/2,y_top+font_nl*2,"Y",font_w,font_h,font_p,font_t, max_level, max_level, max_level)
end

-- title is string
function stamp_title(title)
  -- local font_h  = 200        -- digit height Y taken from script arguments
  local font_w  = font_h/2   -- digit width X
  local font_p  = font_h*3/4 -- pitch (column width) X
  local font_t  = font_h/10  -- segment line thickness
  local font_nl = font_h*3/2 -- line (row width) Y

  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095

  -- centered 500 px square (from parameters)
  --local meter_size_x = 500
  --local meter_size_y = 400

  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2

  -- stamp RGB (color) digits right aligned on the left side
  -- local x_left = rawop.get_jpeg_left()+400
  local x_left = x1+meter_size_x/2-(font_p * #title)/2 -- align center
  -- y_top places string above meter area
  local y_top  = y1-font_nl
  draw_digits(x_left,y_top+font_nl*0,title,font_w,font_h,font_p,font_t, max_level, max_level, max_level)
end

-- shoot, measure and optionally stamp
-- measured rectangular area on the image
-- saves the image with stamping on SD card
-- returns float r,g,b
function shoot_measure_stamp(stamp)
  hook_raw.set(10000)
  press('shoot_half')
  repeat sleep(10) until get_shooting()
  press('shoot_full_only')
  -- wait for the image to be captured
  hook_raw.wait_ready()
  local count, ms = set_yield(-1,-1)
  -- read raw sensor values
  local r,g,b = measure_rgb(stamp)
  if stamp then
    local x = fmath.new(calib_x,1000)
    local y = fmath.new(calib_y,1000)
    local Y = fmath.new(calib_Y,1000)
    stamp_numbers(r,g,b,x,y,Y)
    stamp_title("CAL")
    --stamp_title("123")
  end
  set_yield(count, ms)
  hook_raw.continue()
  release('shoot_full_only')
  release('shoot_half')
  hook_raw.set(0)
  return r,g,b
end

-- set camera to manual
-- place calib material
-- call this funciton
-- gets rgb from sensor, scales to 0-1 float
-- converts float to 1E6 int
-- writes rgb2xyy.txt file
function calib_rgb2xyy()
  read_rgb2xyy_file()
  r,g,b=shoot_measure_stamp(true)
  --print(str1E3(r,7) .. str1E3(g,7) .. str1E3(b,7))
  CALRGB1E6[calib_point][1] = (r*1000000):int()
  CALRGB1E6[calib_point][2] = (g*1000000):int()
  CALRGB1E6[calib_point][3] = (b*1000000):int()
  CALxyY1E6[calib_point][1] = calib_x * 1000
  CALxyY1E6[calib_point][2] = calib_y * 1000
  CALxyY1E6[calib_point][3] = calib_Y * 1000
  local calib_target_name = calib_target[calib_target.index]
  -- if calibration target is Gardner disc
  -- place transparent color in front of camera lens
  -- and point camera to white paper
  if calib_target_name == "Gardner" then
    for i=1,3 do
      CALxyY1E6[calib_point][i] = GARDNER2XY1E4[gardner][i]*100
    end
  end
  if write_rgb2xyy_file() then
    printf("rgb2xyy.txt point %d wr", calib_point)
  else
    print("rgb2xyy.txt error write")
  end
end

-- floats 0-1
function xyY2XYZ(x,y,Y)
  local z = fmath.new(1,1) - x - y
  local X = Y / y * x;
  local Z = Y / y * z;
  return X,Y,Z
end

-- floats 0-1
function XYZ2xyY(X,Y,Z)
  local x = X/(X+Y+Z)
  local y = Y/(X+Y+Z)
  local z = Z/(X+Y+Z)
  return x,y,Y
end

-- input  R,G,B float's 0-1
-- output x,y,Y float's 0-1
function apply_cal_RGB2xyY(R,G,B)
  -- convert int's 0-999999 to float's 0-1
  local fcal_RGB = mat3x3int2float(CALRGB1E6,1000000)
  local fcal_xyY = mat3x3int2float(CALxyY1E6,1000000)
  if over_XYZ then
    -- RGB->XYZ->xyY
    local fcal_XYZ = {{},{},{}}
    -- convert xyY to XYZ
    local X,Y,Z
    for i=1,3 do
      X,Y,Z = xyY2XYZ(fcal_xyY[i][1],fcal_xyY[i][2],fcal_xyY[i][3])
      fcal_XYZ[i] = {X,Y,Z}
    end
    --print("cal RGB")
    --printmat3x3(fcal_RGB)
    --print("cal xyY")
    --printmat3x3(fcal_xyY)
    -- solve eq (matrix inversion)
    local RGB2XYZ = solve_RGB2XYZ(fcal_RGB, fcal_XYZ)
    local XYZ = dotproduct(RGB2XYZ,{R,G,B})
    -- convert XYZ to xyY
    return XYZ2xyY(XYZ[1],XYZ[2],XYZ[3])
  else
    -- direct RGB->xyY without intermediate XYZ
    local RGB2xyY = solve_RGB2XYZ(fcal_RGB, fcal_xyY)
    local xyY = dotproduct(RGB2xyY,{R,G,B})
    return xyY[1],xyY[2],xyY[3]
  end
end
-- **** end calibration ****

-- **** begin colorimetry, normal operation ****
function colorimetry()
  if read_rgb2xyy_file() then
    print("rgb2xyy.txt read")
  else
    print("rgb2xyy.txt not found")
  end
  for i=1,shots do
    hook_raw.set(10000)
    press('shoot_half')
    repeat sleep(10) until get_shooting()
    --click('shoot_full_only')
    press('shoot_full_only')
    -- wait for the image to be captured
    hook_raw.wait_ready()

    local count, ms = set_yield(-1,-1)
    -- sensor values with calibration
    calculate_colorspace()

    set_yield(count, ms)
    hook_raw.continue()
    release('shoot_full_only')
    release('shoot_half')
    hook_raw.set(0)
  end
end
-- **** end colorimetry ****

-- ******** begin shooting logic *********
-- for ptp file exec
if not shots then 
  shots = 1
end

if enable_raw then
  prev_raw_conf=get_raw()
  set_raw(true)
end

-- initialized on in raw hook
--local min_level
--local max_level
--fails=0

if calibrate then
  calib_rgb2xyy()
else
  colorimetry(true)
end

-- restore timporary changed RAW setting
if enable_raw then
  set_raw(prev_raw_conf)
end

-- test_matinv3x3()
-- test_dot3x3()
-- test_RGB2XYZ()
-- print("press key")
if wait_for_key then
  wait_click(0)
end
--sleep(200)
-- ******** end shooting logic *********
