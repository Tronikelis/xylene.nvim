local M = {}

---@class xylene.File
---@field path string
---@field name string
---@field type ("file"|"directory")
---@field opened boolean
---@field depth integer
---@field opened_count integer
---@field parent? xylene.File
---@field children xylene.File[]
local File = {}

---@param dir string
---@return xylene.File[]
function File.dir_to_files(dir)
	---@type xylene.File[]
	local files = {}

	for name, filetype in vim.fs.dir(dir) do
		table.insert(
			files,
			File:new({
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

	table.sort(files, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
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

	for _ = 0, (self.depth * 2) - 1 do
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

---@param row integer
---@param files? xylene.File[]
function Renderer:click(row, files)
	files = files or self.files

	for _, f in ipairs(files) do
		if row == 1 then
			if f.type == "file" then
				vim.cmd.e(f.path)
				return
			end

			f:toggle()
			self:refresh()
			return
		end

		row = row - 1

		if row <= f.opened_count then
			self:click(row, f.children)
			return
		end

		row = row - f.opened_count
	end
end

function Renderer:refresh()
	local opts = vim.bo[self.buf]
	opts.modifiable = true

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

	vim.api.nvim_buf_clear_namespace(self.buf, self.ns_id, 0, -1)
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

	for i, f in ipairs(files) do
		if f.type == "directory" then
			vim.api.nvim_buf_add_highlight(self.buf, self.ns_id, "Directory", i - 1, 0, -1)
		end
	end

	opts.modifiable = false
	opts.modified = false
end

function M.setup()
	vim.api.nvim_create_user_command("Xylene", function()
		local buf = vim.api.nvim_create_buf(false, false)
		local opts = vim.bo[buf]

		opts.filetype = "xylene"

		vim.api.nvim_set_current_buf(buf)

		local cwd = vim.uv.cwd()
		if not cwd then
			return
		end

		local renderer = Renderer:new(cwd, buf)
		renderer:refresh()
	end, {})
end

return M
