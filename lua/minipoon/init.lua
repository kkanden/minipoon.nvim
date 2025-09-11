---@alias RootPath string Path of the project root with an optional git branch appended.
---@alias FileInRoot string Path of the file inside a project.
---@alias MarkPos { row: integer, col: integer } Position of the mark.
---@alias Marks table<FileInRoot, MarkPos> Key-value table of files in project and their current mark position.
---@alias MarksList table<RootPath, Marks> Key-value table of RootPaths with all their existing marks.

local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "minipoon")
local data_file = vim.fs.joinpath(data_dir, "marks.json")

---@as RootPath
local root = vim.fs.root(0, ".git") or vim.uv.cwd()
if not root then
	error("minipoon: couldn't get root directory: ")
	return
end
root = vim.fs.normalize(root)
local root_key = root

local in_git = vim.fs.root(0, ".git") and true or false
if in_git then
	local branch = vim.system({ "git", "branch", "--show-current" }):wait()["stdout"]
	if branch then
		root_key = string.format("%s-%s", root_key, branch)
	end
end

---@as FileInRoot
local current_file = vim.fs.relpath(root, vim.fn.expand("%"))
if not current_file then
	error("minipoon: couldn't get current file path")
	return
end

Marks = setmetatable({}, {})

function Marks:new(tbl)
	tbl = tbl or {}
	setmetatable(tbl, self)
	self.__index = self
	return tbl
end

function Marks:add_mark()
	local row, col = vim.api.nvim_win_get_position(0)
	self[current_file] = { row = row, col = col }
end

function Marks:update_mark()
	self:add_mark()
end

function Marks:get_display()
	return vim.tbl_keys(self)
end

---@as MarksList
local MarksList = {}
setmetatable(MarksList, { __index = {} })

---@param tbl Marks
function MarksList:set_marks(tbl)
	self[root] = tbl
end

---@param root_path RootPath
function MarksList:get_marks(root_path)
	return self[root_path]
end

function MarksList:save_marks()
	local json = vim.json.encode(self)

	local ok, file = pcall(io.open, data_file, "w")
	if not ok or not file then
		error("minipoon: couldn't open data file: " .. file)
		return
	end

	file:write(json)
	file:close()
end

Window = {
	buf = -1,
	win = -1,
}

local function open_window(marks_list, buf, win_config)
	win_config = win_config or {}
	if not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, false)
	end
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false

	---@type vim.api.keyset.win_config
	local default_opts = {
		relative = "editor",
		height = 10,
		width = 50,
		col = math.floor((vim.o.columns - 50) / 2),
		row = math.floor((vim.o.lines - 10) / 2),
		title = " my marks ",
		title_pos = "center",
		border = "rounded",
	}

	local contents = marks_list:get_display()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, contents)

	win_config = vim.tbl_deep_extend("force", win_config, default_opts)
	local win = vim.api.nvim_open_win(buf, true, win_config)

	Window = { buf = buf, win = win }
end

local function setup()
	if vim.fn.isdirectory(data_dir) == 0 then
		vim.fn.mkdir(data_dir, "p")
		vim.fn.writefile({}, data_file)
	end

	vim.api.nvim_create_user_command("MiniPoon", function() end, {})
end

local marks = Marks:new()
marks:add_mark()
open_window(marks, Window.buf, {})

setup()
