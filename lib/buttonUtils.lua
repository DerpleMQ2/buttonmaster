local base64 = require('lib.base64')

local ButtonUtils = {}
ButtonUtils.__index = ButtonUtils

function ButtonUtils.serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then
        if type(name) ~= 'number' then name = '"' .. name .. '"' end
        tmp = tmp .. '[' .. name .. '] = '
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp = tmp ..
                ButtonUtils.serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

function ButtonUtils.encodeTable(tbl)
    return base64.enc('return ' .. ButtonUtils.serializeTable(tbl))
end

function ButtonUtils.decodeTable(encString)
    local decodedStr = base64.dec(encString)
    local success, decodedTable = pcall(load(decodedStr))
    if not success or not type(decodedTable) == 'table' then
        print('\arERROR: Failed to import object!\ax')
        return false, nil
    end
    return true, decodedTable
end

function ButtonUtils.tableContains(t, v)
    if not t then return false end
    for _, tv in pairs(t) do
        if tv == v then return true end
    end
    return false
end

function ButtonUtils.dumpTable(o, depth)
    if not depth then depth = 0 end
    if type(o) == 'table' then
        local s = '{ \n'
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. string.rep(" ", depth) .. '\t[' .. k .. '] = ' .. ButtonUtils.dumpTable(v, depth + 1) .. ',\n'
        end
        return s .. string.rep(" ", depth) .. '}'
    else
        return tostring(o)
    end
end

function ButtonUtils.getTableSize(tbl)
    local cnt = 0
    if tbl ~= nil then
        for k, v in pairs(tbl) do cnt = cnt + 1 end
    end
    return cnt
end

return ButtonUtils
