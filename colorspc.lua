--[[
@title COLOR SPACE RGB->xyY (CIE)
@chdk_version 1.6
#calibrate=false "Calibrate"
#calib_point=1 "Calib point" [1 3]
#calib_target=xyY "Calib target" {Gardner xyY RGB} table
#calib_r=200 "Calib Red"   [0 999]
#calib_g=200 "Calib Green" [0 999]
#calib_b=200 "Calib Blue"  [0 999]
#calib_x=333 "Calib x"  [0 999]
#calib_y=333 "Calib y"  [0 999]
#calib_Y=333 "Calib Y"  [0 999]
#gardner=11 "Calib Gardner" [1 18]
#illuminant=CIE_E "RGB_Illuminant" {Adobe_D65 Apple_D65 ColorMatch_D50 ECI_D50 Ekta_D50 ProPhoto_D50 SMPTEC_D65 REC709 sRGB_D65 CIE_E} table
#inverse_gamma=None "Inverse gamma" {REC709 sRGB None} table
#meter_size_x=500 "Meter width X"  [20 999]
#meter_size_y=400 "Meter height Y" [20 999]
#font_h=200 "Font height" [10 1000]
#enable_raw=false "Enable raw"
#shots=1 "Shots" -- number of successive shots
]]

-- for known camera it is recommended to
-- hardcode illuminant and inverse_gamma
-- to avoid misconfiguration
-- SX280HS
-- illuminant="CIE_E"
-- inverse_gamma="None"

-- shots=1 -- hardcode always 1 shot

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

-- **** begin inverse gamma ***
IGAMMA1E5 =
{ --            div_lin  thresh   add     div     pow
  ["None"]   = { 100000, 100000,    0, 100000, 100000  },
  ["sRGB"]   = {1292000,   4045, 5500, 105500, 240000  },
  ["REC709"] = { 450000,   8100, 9900, 109900, 222222  },
}

-- inverse gamma
-- some image sensor may apply gamma function.
-- 3 different exposure bracketings should produce same xy
-- experimentally it is found that for SX280HS camera
-- "None" inverse gamma function fits best for same xy
-- for different exposure and/or light intensity.
-- this function should remove gamma and returns linear RGB
-- input  gamma RGB (float 0-1) (128-4095 should be scaled to 0-1)
-- output linear RGB (float 0-1)
function invgamma(var)
  -- https://en.wikipedia.org/wiki/SRGB
  -- is this non-linear to linear formula (inverse)?
  -- see for Rec.709: https://en.wikipedia.org/wiki/Rec._709
  local inverse_gamma_name = inverse_gamma[inverse_gamma.index]
  local gama_div1   =  fmath.new(IGAMMA1E5[inverse_gamma_name][1],100000) -- 12.92
  local gama_thresh =  fmath.new(IGAMMA1E5[inverse_gamma_name][2],100000) --  0.04045
  local gama_add    =  fmath.new(IGAMMA1E5[inverse_gamma_name][3],100000) --  0.05500
  local gama_div    =  fmath.new(IGAMMA1E5[inverse_gamma_name][4],100000) --  1.055
  local gama_pow    =  fmath.new(IGAMMA1E5[inverse_gamma_name][5],100000) --  2.400

  if var > gama_thresh then
    var = ((var + gama_add) / gama_div) ^ gama_pow
  else
    var = var / gama_div1
  end

  return var
end
-- **** end inverse gamma coefficiens ***

-- **** begin color space conversion ****
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
  ["sRGB_D65"] = -- sRGB, D65 https://en.wikipedia.org/wiki/SRGB
  {
    {4124564,  3575761,  1804375},
    {2126729,  7151522,   721750},
    { 193339,  1191920,  9503041},
  },
  ["REC709"] = -- similar to sRGB_D65 https://community.intel.com/t5/Intel-Integrated-Performance/RGB-to-XYZ/td-p/1144785
  {
    {4124530,  3575800,  1804230},
    {2126710,  7151600,   721690},
    { 193340,  1191930,  9502270},
  },
  ["SMPTEC_D65"] = -- SMPTE-C, D65
  {
    {3935891,  3652497,  1916313},
    {2124132,  7010437,   865432},
    { 187423,  1119313,  9581563},
  },
}

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

-- colorspace conversion formula
-- input RGB fmath 0-1
-- output XYZ fmath 0-1
function rgb2xyz(R,G,B)
  -- conversion matrix
  -- see http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
  -- depends on standard viewpoint and light source
  -- Observer = 2°, Illuminant = D65
  local illuminant_name = illuminant[illuminant.index]
  local m = mat3x3int2float(RGB2XYZ1E7[illuminant_name], 10000000)
  local p = dotproduct(m,{R,G,B})
  return p[1],p[2],p[3] -- XYZ
end
-- ******** end color space conversion *********


-- ******** begin image processing *********
-- colorimetry calculation
-- temporary display on screen
-- markings on saved picture
-- TODO if use_cal==true then apply calibration using CALRGB1E6
function calculate_colorspace(use_cal)
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

  local i_r, i_g1, i_g2, i_g, i_b
  i_r  = (r-min_level)
  i_g  = (g1+g2)/2-min_level
  i_b  = (b-min_level)
  local i_range = max_level-min_level

  -- float rgb range 0-1
  local r,g,b
  r = invgamma(fmath.new(i_r,i_range)) -- i_r / i_range
  g = invgamma(fmath.new(i_g,i_range)) -- i_g / i_range
  b = invgamma(fmath.new(i_b,i_range)) -- i_b / i_range

  -- TODO should calibration be applied before gamma?
  -- for inverse_gamma = "None" it doesn't matter is it before or after.
  -- apply calibration
  if use_cal then
    r,g,b = apply_cal(r,g,b)
  end

  -- fixed rgb value for debugging
  -- For Illuminant "CIE_E" and r=g=b=0.5
  -- CIE values should be x=0.333 y=0.333
  --r=fmath.new(1,2) -- 1/2 = 0.5
  --g=r
  --b=r

  local CIE_X,CIE_Y,CIE_Z
  CIE_X,CIE_Y,CIE_Z = rgb2xyz(r,g,b)

  -- from XYZ calculate xyz
  local CIE_x,CIE_y,CIE_z
  CIE_x = CIE_X / (CIE_X+CIE_Y+CIE_Z)
  CIE_y = CIE_Y / (CIE_X+CIE_Y+CIE_Z)
  CIE_z = CIE_Z / (CIE_X+CIE_Y+CIE_Z)

  -- draw RGB (color) digits right aligned on the left side
  -- local x_left = rawop.get_jpeg_left()+400
  local x_left = x1-font_p*7
  -- y_top centers digits in y axis
  local y_top  = (y1+meter_size_y/2)-font_nl*3/2+(font_nl-font_h)/2
  draw_digits(x_left,y_top+font_nl*0,str1E3(r,6),font_w,font_h,font_p,font_t, max_level, min_level, min_level)
  draw_digits(x_left,y_top+font_nl*1,str1E3(g,6),font_w,font_h,font_p,font_t, min_level, max_level, min_level)
  draw_digits(x_left,y_top+font_nl*2,str1E3(b,6),font_w,font_h,font_p,font_t, min_level, min_level, max_level)

  -- draw xy (white) digits left aligned on the right side
  local x_right = x1+meter_size_x+font_p
  draw_digits(x_right,y_top+font_nl*0,str1E3(CIE_x),font_w,font_h,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right,y_top+font_nl*1,str1E3(CIE_y),font_w,font_h,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right,y_top+font_nl*2,str1E3(CIE_Y),font_w,font_h,font_p,font_t, max_level, max_level, max_level)

  -- font size calc for lowercase "xy" and uppercase "Y"
  draw_digits(x_right+font_p*11/2,y_top+font_nl*0+font_h/4,"X",font_w*3/4,font_h*3/4,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right+font_p*11/2,y_top+font_nl*1+font_h/4,"Y",font_w*3/4,font_h*3/4,font_p,font_t, max_level, max_level, max_level)
  draw_digits(x_right+font_p*11/2,y_top+font_nl*2,"Y",font_w,font_h,font_p,font_t, max_level, max_level, max_level)

  set_console_layout(0,0,40,12)
  --printf("meter r=%d g1=%d g2=%d b=%d",r,g1,g2,b)
  --printf("gardner %d: x=0.%d y=0.%d", gardner, GARDNER2XY1E4[gardner][1], GARDNER2XY1E4[gardner][2] )
  --printf("black=%d white=%d", min_level, max_level)
  printf("R=%s G=%s B=%s",str1E3(r,6),str1E3(g,6),str1E3(b,6))
  printf("x=%s y=%s Y=%s (CIE)",str1E3(CIE_x,6),str1E3(CIE_y,6),str1E3(CIE_Y,6))
  --logfile=io.open("A/colorspc.log","wb")
  --logfile:write(string.format("illuminant = >>%s<<\n", illuminant[illuminant.index]))
  --logfile:write(string.format("meter r=%d g1=%d g2=%d b=%d\n",r,g1,g2,b))
  --logfile:write(string.format("meter r=%s g1=%s g2=%s b=%s\n",str1E3(i_r),str1E3(i_g1),str1E3(i_g2),str1E3(i_b)))
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

-- file COLORCAL.TXT contains serialized CALRGB1E6 array
-- example:
-- 999999 -- R exp. 1/x
-- 999999 -- G exp. 1/x
-- 999999 -- B exp. 1/x
-- 499999 -- R exp. 1/2x
-- 499999 -- G exp. 1/2x
-- 499999 -- B exp. 1/2x
--      0 -- R exp. 1/4x
--      0 -- G exp. 1/4x
--      0 -- B exp. 1/4x
function write_cal_file()
  local calfile=io.open("A/colorcal.txt","wb")
  if calfile then
    for i=1,3 do
      for j=1,3 do
        calfile:write(string.format("%d ", CALRGB1E6[i][j]))
      end
      calfile:write("\n")
    end
    calfile:close()
    return true
  end
  return false
end

function read_cal_file()
  local calfile=io.open("A/colorcal.txt","rb")
  if calfile then
    for i=1,3 do
      for j=1,3 do
        CALRGB1E6[i][j] = calfile:read("*n")
      end
    end
    calfile:close()
    return true
  end
  return false
end

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

-- return r,g,b floats
function measure_rgb()
  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095

  -- centered 500 px square (from parameters)
  --local meter_size_x = 500
  --local meter_size_y = 400

  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2

  local r,g1,b,g2 = rawop.meter_rgbg(x1,y1,meter_size_x/2,meter_size_y/2,2,2)
  print(string.format("r=%d g1=%d g2=%d b=%d",r,g1,g2,b))
  fr = fmath.new(        r-min_level,max_level-min_level)
  fg = fmath.new((g1+g2)/2-min_level,max_level-min_level)
  fb = fmath.new(        b-min_level,max_level-min_level)

  return fr,fg,fb
end

function draw_meter_square()
  local min_level = rawop.get_black_level() --  128
  local max_level = rawop.get_white_level() -- 4095
  local x1 = rawop.get_raw_width()/2 - meter_size_x/2
  local y1 = rawop.get_raw_height()/2 - meter_size_y/2
  -- draw white rectangle around metered area
  rawop.rect_rgbg(x1-2,y1-2,meter_size_x+4,meter_size_y+4,2,max_level,max_level,max_level)
  -- draw small coloured boxes at 4 corners of metered area
  --rawop.fill_rect_rgbg(x1,y1,16,16,r,min_level,min_level)
  --rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1,16,16,min_level,g1,min_level)
  --rawop.fill_rect_rgbg(x1,y1 + meter_size_y - 16,16,16,min_level,g2,min_level)
  --rawop.fill_rect_rgbg(x1 + meter_size_x - 16,y1 + meter_size_y - 16,16,16,min_level,min_level,b)
end

-- shoot, measure and optionally draw
-- measured rectangular area on the image
-- saves the image with drawing on SD card
-- returns float r,g,b
function shoot_measure_draw(draw)
  hook_raw.set(10000)
  press('shoot_half')
  repeat sleep(10) until get_shooting()
  press('shoot_full_only')
  -- wait for the image to be captured
  hook_raw.wait_ready()
  local count, ms = set_yield(-1,-1)
  -- read raw sensor values
  local r,g,b
  r,g,b=measure_rgb()
  if draw then
    draw_meter_square()
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
function calib_rgb2xyz()
  read_rgb2xyy_file()
  r,g,b=shoot_measure_draw(true)
  print(str1E3(r,7) .. str1E3(g,7) .. str1E3(b,7))
  CALRGB1E6[calib_point][1] = (r*1000000):int()
  CALRGB1E6[calib_point][2] = (g*1000000):int()
  CALRGB1E6[calib_point][3] = (b*1000000):int()
  if write_rgb2xyy_file() then
    printf("rgb2xyy.txt point %d wr", calib_point)
  else
    print("rgb2xyy.txt error write")
  end
end

function calibration()
  press('shoot_half')
  repeat sleep(10) until get_shooting()
  afl_av=get_av96()
  afl_sv=get_sv96()
  afl_tv=get_tv96()
  release('shoot_half')
  -- set_aflock(1) -- focus lock - no more change of the focus

  CALRGB1E6={{},{},{}} -- we will get here bracketed values
  for i=1,3 do -- 3 shots for bracketing
    shoot() -- fix this more elegant way
    -- with shoot() for 3 loops we get 6 pics.
    -- first pic without 7-seg numbers and second with 7-seg numbers.
    -- all pics can be erased later.
    -- For calibration this is usually not a big drawback.
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
    -- get sensor values without calibration thus (false) argument
    r,g,b = calculate_colorspace(false)
    -- convert float's to int's
    CALRGB1E6[i][1], CALRGB1E6[i][2], CALRGB1E6[i][3] = (r*1000000):int(),(g*1000000):int(),(b*1000000):int()
    set_yield(count, ms)

    hook_raw.continue()
    release('shoot_full_only')
    release('shoot_half')
    hook_raw.set(0)
    -- set_aflock(0)
    -- sleep(1900)
  end -- for shots

  -- restore values
  set_tv96(afl_tv)
  set_sv96(afl_sv)
  set_av96(afl_av)
  set_aflock(0)

  -- now we have all the sensor values ready in CALRGB1E6[1..3][1..3]
  -- CALRGB1E6[number_of_shots][1-red, 2-green, 3-blue]
  -- we can interpolate them for a white balance
  -- R,G,B = apply_cal(CALRGB1E6[1][1], CALRGB1E6[1][2], CALRGB1E6[1][3])
  -- write calib data to file
  if write_cal_file() then
    print("colorcal.txt written")
  else
    print("colorcal.txt write error")
  end
end

-- convert input RGB (0-99999)
-- to calibrated RGB values using CALRGB1E6
-- TODO parabolic 3-point interpolation
-- input  R,G,B float's 0-1
-- output R,G,B float's 0-1
function apply_cal(R,G,B)
  -- convert int's 0-999999 to float's 0-1
  fcal_rgb = mat3x3int2float(CALRGB1E6,1000000)

  -- reference calibration target color is given as script parameters
  -- convert from RGB int's 0-999 to float's 0-1
  local target = {}
  target[1] = fmath.new(calib_r,1000)
  target[2] = fmath.new(calib_g,1000)
  target[3] = fmath.new(calib_b,1000)

  local calib_target_name = calib_target[calib_target.index]
  -- print("target name", calib_target_name)
  local cal_x = fmath.new(calib_x,1000)
  local cal_y = fmath.new(calib_y,1000)
  local cal_Y = fmath.new(calib_Y,1000)

  -- calibration target is Gardner disc
  -- place transparent color in front of camera lens
  -- and point camera to white paper
  if calib_target_name == "Gardner" then
    cal_x = fmath.new(GARDNER2XY1E4[gardner][1],10000)
    cal_y = fmath.new(GARDNER2XY1E4[gardner][2],10000)
    cal_Y = fmath.new(GARDNER2XY1E4[gardner][3],10000)
    calib_target_name = "xyY"
  end

  if calib_target_name == "xyY" then
    -- from xy to RGB target using inverse matrix
    --local xyz2rgb1E7 = {
    --  {32404542,-15371385,-4985314},
    --  {-9692660, 18760108,  415560},
    --  {  556434,  2040259,10572272}}
    --xyz2rgb = mat3x3int2float(xyz2rgb1E7,10000000)
    local illuminant_name = illuminant[illuminant.index]
    local m = mat3x3int2float(RGB2XYZ1E7[illuminant_name],10000000)
    local x = cal_x
    local y = cal_y
    local z = fmath.new(1,1) - x - y
    local Y = cal_Y
    local X = Y / y * x;
    local Z = Y / y * z;
    target = dotproduct(matinv3x3(m),{X,Y,Z})
    --target = dotproduct(xyz2rgb,{X,Y,Z})
  end

  -- currently only 1st and 2nd bracketing values are used
  -- for linear interpolation a*x+b
  -- TODO parabolic 3-point interpolation a*x*x+b*x+c
  local a = {}
  local b = {}
  -- a*fcal_rgb[1][j]+b = target[j]
  -- a*fcal_rgb[2][j]+b = target[j]/2
  -- a*fcal_rgb[3][j]+b = target[j]/4
  -- a*x1+b = t
  -- a*x2+b = t/2
  -- b = t-a*x1
  -- a*x2+t-a*x1 = t/2
  -- a*(x2-x1)+t = t/2
  -- a*(x2-x1) = (1/2-1)*t
  -- a*(x1-x2) = (1-1/2)*t
  -- a = (1-1/2)*t/(x1-x2)
  -- a = (1-1/4)*t/(x1-x3)
  -- a = (1-1/2)*t/(x1-x3) -- or maybe this
  for j=1,3 do
    a[j] = (fmath.new(1,1)-fmath.new(1,2))*target[j]/(fcal_rgb[1][j]-fcal_rgb[3][j])
    b[j] = target[j]-a[j]*fcal_rgb[1][j]
  end

  R = R * a[1] + b[1]
  G = G * a[2] + b[2]
  B = B * a[3] + b[3]

  return R,G,B
end
-- **** end calibration ****

-- **** begin colorimetry, normal operation ****
function colorimetry()
  if read_cal_file() then
    print("colorcal.txt read")
  else
    print("colorcal.txt not found")
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
    calculate_colorspace(true)

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
  --calibration()
  calib_rgb2xyz()
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
wait_click(0)

--sleep(200)
-- ******** end shooting logic *********
