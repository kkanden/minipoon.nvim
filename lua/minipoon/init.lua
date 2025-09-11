---@alias RootPath string Path of the project root with an optional git branch appended.
---@alias FileInRoot string Path of the file inside a project.
---@alias MarkPos { row: integer, col: integer } Position of the mark.
---@alias Marks table<FileInRoot, MarkPos> Key-value table of files in project and their current mark position.
---@alias MarksList table<RootPath, Marks> Key-value table of RootPaths with all their existing marks.

-- setup
local menu_id = math.random(100000)
local data_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "minipoon")
local data_file = vim.fs.joinpath(data_dir, "marks.json")

if vim.fn.isdirectory(data_dir) == 0 then
	vim.fn.mkdir(data_dir, "p")
	vim.fn.writefile({ "{}" }, data_file)
elseif vim.fn.filereadable(data_file) == 0 then
	vim.fn.writefile({ "{}" }, data_file)
end

local lines = vim.fn.readfile(data_file)
lines = table.concat(lines) -- vim.json.decode needs a pure string
---@type Marks
local marks_list_global = vim.json.decode(lines)

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

-- functionality
local function get_menu_name()
	menu_id = menu_id + 1
	return "__minipoon__" .. menu_id
end
local Marks = {}

local window = {
	buf = -1,
	win = -1,
}

function Marks:new()
	if not marks_list_global[root_key] then
		marks_list_global[root_key] = {}
	end
	local marks = setmetatable({
		root = root,
		win_config = {},
		list = marks_list_global[root_key],
	}, {
		__index = Marks,
	})
	return marks
end

-- function Marks:_update_mark()
-- 	self:add_mark()
-- end

function Marks:_get_display()
	return vim.tbl_keys(self.list)
end

function Marks:_get_pos(mark_entry_name)
	local pos = self.list[mark_entry_name]
	return pos.row, pos.col
end

function Marks:_update_marks(marks_to_keep)
	for k, _ in pairs(self.list) do
		if not vim.tbl_contains(marks_to_keep, k) then
			self.list[k] = nil
		end
	end
end

function Marks:_open(mark_entry_name)
	self:toggle_window()

	local file_path = mark_entry_name
	if vim.fn.isabsolutepath(file_path) == 0 then
		file_path = vim.fs.joinpath(self.root, file_path)
	end
	local buf = vim.fn.bufnr(file_path)
	local should_set_cursor = false
	if buf == -1 then
		should_set_cursor = false
		buf = vim.fn.bufadd(file_path)
	end

	if not vim.api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
	end

	vim.api.nvim_set_current_buf(buf)

	if should_set_cursor then
		local pos = self:_get_pos(mark_entry_name)
		vim.api.nvim_win_set_cursor(0, pos)
	end
end

function Marks:add_mark()
	local full_file_path = vim.fn.expand("%:p")
	---@type FileInRoot
	local current_file = vim.fs.relpath(root, full_file_path) or full_file_path
	local row, col = vim.api.nvim_win_get_cursor(0)
	self.list[current_file] = { row = row, col = col }
end

function Marks:close_window()
	vim.api.nvim_win_hide(window.win)
end

function Marks:toggle_window()
	local buf = window.buf
	local win = window.win
	local win_config = self.win_config or {}

	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_hide(win)
		return
	end

	if not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, false)
	end

	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "minipoon"
	vim.bo[buf].buftype = "acwrite"

	if vim.api.nvim_buf_get_name(buf) == "" then
		vim.api.nvim_buf_set_name(buf, get_menu_name())
	end

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			local entries = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			self:_update_marks(entries)
		end,
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		callback = function()
			local entries = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			self:_update_marks(entries)
		end,
	})

	vim.keymap.set("n", "<CR>", function()
		local entry = vim.api.nvim_get_current_line()
		self:_open(entry)
	end, { buffer = buf })

	vim.keymap.set("n", "q", function()
		self:close_window()
	end, { buffer = buf })

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

	local contents = self:_get_display()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, contents)

	win_config = vim.tbl_deep_extend("force", win_config, default_opts)
	local win = vim.api.nvim_open_win(buf, true, win_config)
	window = { buf = buf, win = win }
end

local marks = Marks:new()
return marks
