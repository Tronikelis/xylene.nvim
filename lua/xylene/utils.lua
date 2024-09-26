local M = {}

---@param str string
---@param starts_with string
---@return boolean
function M.string_starts_with(str, starts_with)
    return string.sub(str, 1, string.len(starts_with)) == starts_with
end

---@param name string
---@return string?
function M.file_extension(name)
    local dot = vim.split(name, ".", { trimempty = true })
    if #dot == 0 then
        return nil
    end

    return dot[#dot]
end

return M
