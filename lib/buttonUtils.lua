local base64 = require('lib.base64')

local ButtonUtils = {}
ButtonUtils.__index = ButtonUtils

function ButtonUtils.serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

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
    local success, decodedTable = pcall(loadstring(decodedStr))
    if not success or not type(decodedTable) == 'table' then
        print('\arERROR: Failed to import event\ax')
        return nil
    end
    return decodedTable
end

return ButtonUtils
