local utils = require("xylene.utils")

local M = {
    ---@class xylene.Config
    ---@field indent integer
    ---@field icons boolean
    ---@field sort_names fun(a: xylene.File, b: xylene.File): boolean
    config = {
        icons = true,
        indent = 4,
        sort_names = function(a, b)
            return a.name < b.name
        end,
    },
}

---@class xylene.File
---@field path string
---@field name string
---@field type ("file"|"directory")
---@field opened boolean
---@field depth integer
---@field opened_count integer
---@field icon? string
---@field icon_hl? string
---@field parent? xylene.File
---@field children xylene.File[]
local File = {}

function File:indent_len()
    return self.depth * M.config.indent
end

---@param dir string
---@return xylene.File[]
function File.dir_to_files(dir)
    ---@type xylene.File[]
    local files = {}

    for name, filetype in vim.fs.dir(dir) do
        ---@type string?, string?
        local icon, icon_hl

        if package.loaded["nvim-web-devicons"] and M.config.icons then
            local icons = require("nvim-web-devicons")

            local ext = utils.file_extension(name)
            icon, icon_hl = icons.get_icon(name, ext, { default = true })
        end

        table.insert(
            files,
            File:new({
                icon = icon,
                icon_hl = icon_hl,

                opened_count = 0,
                depth = 0,
                name = name,
                path = vim.fs.joinpath(dir, name),
                type = filetype,
                opened = false,
                children = {},
            })
        )
    end

    table.sort(files, M.config.sort_names)
    table.sort(files, function(a, b)
        return a.type < b.type
    end)

    return files
end

---@param obj xylene.File
---@return xylene.File
function File:new(obj)
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function File:calc_opened_count()
    self.opened_count = #self.children
    for _, f in ipairs(self.children) do
        self.opened_count = self.opened_count + f.opened_count
    end
end

function File:open_compact()
    local name = self.name
    local path = self.path

    while #self.children == 1 and self.children[1].type == "directory" do
        local child = self.children[1]

        name = vim.fs.joinpath(name, child.name)
        path = child.path

        self.children = File.dir_to_files(child.path)
    end

    self.name = name
    self.path = path
end

function File:open()
    if self.type ~= "directory" or self.opened then
        return
    end
    self.opened = true

    if #self.children == 0 then
        self.children = File.dir_to_files(self.path)
        self:open_compact()

        for _, f in ipairs(self.children) do
            f.depth = self.depth + 1
            f.parent = self
        end
    end

    self:calc_opened_count()

    self:traverse_parent(function(file)
        file.opened_count = file.opened_count + self.opened_count
    end)
end

---@param fn fun(file: xylene.File)
function File:traverse_parent(fn)
    local parent = self.parent
    while parent do
        fn(parent)
        parent = parent.parent
    end
end

function File:close()
    self.opened = false

    self:traverse_parent(function(file)
        file.opened_count = file.opened_count - self.opened_count
    end)

    self.opened_count = 0
end

function File:toggle()
    if self.opened then
        self:close()
    else
        self:open()
    end
end

---@param files? xylene.File[]
---@return xylene.File[]
function File:flatten_opened(files)
    files = files or {}

    table.insert(files, self)

    if self.type == "directory" and not self.opened then
        return files
    end

    for _, f in ipairs(self.children) do
        f:flatten_opened(files)
    end

    return files
end

function File:line()
    local str = self.name

    if self.type == "directory" then
        if self.opened then
            str = "- " .. str
        else
            str = "+ " .. str
        end

        str = str .. "/"
    end

    if self.icon and self.type ~= "directory" then
        str = self.icon .. " " .. str
    end

    for _ = 0, self:indent_len() - 1 do
        str = " " .. str
    end

    return str
end

---@class xylene.Renderer
---@field buf integer
---@field ns_id integer
---@field files xylene.File[]
local Renderer = {}

---@param dir string
---@param buf integer
---@return xylene.Renderer
function Renderer:new(dir, buf)
    ---@type xylene.Renderer
    local obj = {
        files = File.dir_to_files(dir),
        buf = buf,
        ns_id = vim.api.nvim_create_namespace(""),
    }

    vim.keymap.set("n", "<cr>", function()
        local row = table.unpack(vim.api.nvim_win_get_cursor(0))
        obj:click(row)
    end, { buffer = buf })

    setmetatable(obj, self)
    self.__index = self

    return obj
end

---@param fn fun()
function Renderer:with_modifiable(fn)
    local opts = vim.bo[self.buf]

    opts.modifiable = true
    fn()
    opts.modifiable = false
    opts.modified = false
end

---@param dir xylene.File
---@param row integer
function Renderer:toggle_and_render_dir(dir, row)
    local from = row - 1
    local to = dir.opened_count + 1 + from
    dir:toggle()

    local lines = {}
    local files = dir:flatten_opened()

    for _, f in ipairs(files) do
        table.insert(lines, f:line())
    end

    self:with_modifiable(function()
        vim.api.nvim_buf_set_lines(self.buf, from, to, true, lines)
        self:apply_hl(files, from)
    end)
end

---@param row integer
---@param files? xylene.File[]
---@param row_needle? integer
function Renderer:click(row, row_needle, files)
    files = files or self.files
    row_needle = row_needle or row

    --- this could be a perf bottleneck
    --- as worst case scenario it loops through the whole root files

    for _, f in ipairs(files) do
        if row_needle == 1 then
            if f.type == "file" then
                vim.cmd.e(f.path)
                return
            end

            self:toggle_and_render_dir(f, row)
            return
        end

        row_needle = row_needle - 1

        if row_needle <= f.opened_count then
            self:click(row, row_needle, f.children)
            return
        end

        row_needle = row_needle - f.opened_count
    end
end

---@param flattened_files xylene.File[]
---@param offset integer
function Renderer:apply_hl(flattened_files, offset)
    for i, f in ipairs(flattened_files) do
        local line = offset + i - 1

        if f.type == "directory" then
            vim.api.nvim_buf_add_highlight(self.buf, self.ns_id, "XyleneDir", line, 0, -1)
        else
            if f.icon and f.icon_hl then
                local start = f:indent_len()
                vim.api.nvim_buf_add_highlight(self.buf, self.ns_id, f.icon_hl, line, start, start + 1)
            end
        end
    end
end

function Renderer:refresh()
    ---@type string[]
    local lines = {}
    ---@type xylene.File[]
    local files = {}

    for _, file in ipairs(self.files) do
        for _, l in ipairs(file:flatten_opened()) do
            table.insert(lines, l:line())
            table.insert(files, l)
        end
    end

    self:with_modifiable(function()
        vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
        self:apply_hl(files, 0)
    end)
end

---returns [file: xylene.File?, row: integer]
---@param filepath string
---@param files? xylene.File[]
---@param line? integer
---@return [xylene.File?, integer]
function Renderer:open_from_filepath(filepath, files, line)
    files = files or self.files
    line = line or 0

    for _, f in ipairs(files) do
        line = line + 1

        if f.path == filepath then
            return { f, line }
        end

        if utils.string_starts_with(filepath, f.path) then
            if #f.children == 0 then
                f:open()
            end

            return self:open_from_filepath(filepath, f.children, line)
        end
    end

    return { nil, 0 }
end

function M.setup(config)
    config = config or {}
    M.config = vim.tbl_deep_extend("force", M.config, config)

    vim.api.nvim_set_hl(0, "XyleneDir", { link = "Directory" })

    vim.api.nvim_create_user_command("Xylene", function(args)
        local buf = vim.api.nvim_create_buf(false, false)

        local opts = vim.bo[buf]
        opts.filetype = "xylene"

        local cwd = vim.uv.cwd()
        if not cwd then
            return
        end

        local filepath = vim.fn.expand("%:p")
        vim.api.nvim_set_current_buf(buf)

        local renderer = Renderer:new(cwd, buf)

        if args.bang then
            local from_filepath = renderer:open_from_filepath(filepath)

            renderer:refresh()

            if not from_filepath[1] then
                return
            end

            vim.api.nvim_win_set_cursor(0, { from_filepath[2], from_filepath[1]:indent_len() })
        else
            renderer:refresh()
        end
    end, {
        bang = true,
    })
end

return M
