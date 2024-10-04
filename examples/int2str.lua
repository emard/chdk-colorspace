-- Int2Str function is obsolete
-- included here as programming example
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
