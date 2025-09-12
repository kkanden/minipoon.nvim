---@alias RootPath string Absolute path of the project root with an optional git branch appended.
---@alias FilePath string Path of a file, relative if inside project, absolute otherwise.
---@alias MarkPos { row: integer, col: integer } Position of the mark.
---@alias Marks table<FilePath, MarkPos> Key-value table of files in project and their mark position.
---@alias MarksList table<RootPath, Marks> Key-value table of RootPaths with all their existing marks.

-- setup
local augroup = vim.api.nvim_create_augroup("minipoon", {})
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
---@type MarksList
local marks_list_global = vim.json.decode(lines)

---@return RootPath
local function get_root()
	local cwd = vim.uv.cwd() or 0 -- if for some reason couldn't get cwd use current buffer
	local git_root = vim.fs.root(cwd, ".git")
	local root = git_root or vim.uv.cwd()
	if not root then
		error("minipoon: couldn't get root directory")
	end
	root = vim.fs.normalize(root)
	return root
end

---@param root RootPath
local function make_root_key(root)
	local git_root = vim.fs.root(0, ".git")
	if not git_root then
		return root
	end
	local root_key = root
	local branch = vim.system({ "git", "branch", "--show-current" }):wait()["stdout"]:gsub("\n", "")
	if branch and branch ~= "" then
		root_key = string.format("%s-%s", root_key, branch)
	end
	return root_key
end

---@param root RootPath
---@return FilePath
local function get_current_file(root)
	local full_file_path = vim.fn.expand("%:p")
	---@type FilePath
	local current_file = vim.fs.relpath(root, full_file_path) or full_file_path
	return current_file
end

-- functionality
local menu_id = math.random(100000)
local function get_menu_name()
	menu_id = menu_id + 1
	return "__minipoon__" .. menu_id
end

local window = {
	buf = -1,
	win = -1,
}

local Marks = {}

function Marks:new()
	local marks = setmetatable({
		root = get_root(),
		win_config = {},
		list = marks_list_global,
	}, {
		__index = Marks,
	})
	return marks
end

---@return Marks
function Marks:_get_list()
	local root_key = make_root_key(self.root)
	if not self.list[root_key] then
		self.list[root_key] = {}
	end
	return self.list[root_key]
end

---@param list Marks
function Marks:_set_list(list)
	local root_key = make_root_key(self.root)
	self.list[root_key] = list
end

function Marks:_get_next_index()
	return vim.tbl_count(self:_get_list()) + 1
end

---@return FilePath[]
function Marks:_get_mark_names()
	local mark_names = {}
	local list = self:_get_list()
	for i = 1, vim.tbl_count(list) do
		local mark = list[i]
		local mark_name = vim.tbl_keys(mark)[1]
		table.insert(mark_names, mark_name)
	end
	return mark_names
end

---@param mark_name FilePath
---@return integer?
function Marks:_get_index_from_mark(mark_name)
	for i, v in ipairs(self:_get_mark_names()) do
		if v == mark_name then
			return i
		end
	end
	return nil
end

---@param index integer
---@return FilePath
function Marks:_get_mark_name_from_index(index)
	return vim.tbl_keys(self:_get_list()[index])[1]
end

---@param mark_name FilePath
---@return MarkPos
function Marks:_get_pos(mark_name)
	local tbl = vim.tbl_values(self:_get_list())
	local pos_tbl = vim.iter(tbl)
		:filter(function(x)
			return vim.tbl_keys(x)[1] == mark_name
		end)
		:totable()
	local pos = pos_tbl[1][mark_name]
	return { row = pos.row, col = pos.col }
end

---@param mark_name FilePath
---@return boolean
function Marks:_mark_in_list(mark_name)
	return vim.tbl_contains(self:_get_mark_names(), mark_name)
end

---@param marks_to_keep FilePath[]
function Marks:_update_marks(marks_to_keep)
	local mark_list = {}

	-- filtering
	for i, filename in ipairs(marks_to_keep) do
		if self:_mark_in_list(filename) then
			local mark_index = self:_get_index_from_mark(filename)
			mark_list[i] = self:_get_list()[mark_index]
		end
	end

	self:_set_list(mark_list)
end

---@param mark_name FilePath
function Marks:_open(mark_name)
	if vim.api.nvim_win_is_valid(window.win) then
		self:close_window()
	end

	local file_path = mark_name
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
		local pos = self:_get_pos(mark_name)
		vim.api.nvim_win_set_cursor(0, { pos.row, pos.col })
	end
end

function Marks:add_mark()
	local current_file = get_current_file(self.root)
	local index = self:_get_index_from_mark(current_file) or self:_get_next_index()
	local pos = vim.api.nvim_win_get_cursor(0)
	self:_get_list()[index] = { [current_file] = { row = pos[1], col = pos[2] } }
end

function Marks:close_window()
	if vim.api.nvim_win_is_valid(window.win) then
		vim.api.nvim_win_close(window.win, true)
	end
end

---@param index integer
function Marks:open_at(index)
	local mark_name = self:_get_mark_name_from_index(index)
	self:_open(mark_name)
end

function Marks:toggle_window()
	local buf = window.buf
	local win = window.win
	local win_config = self.win_config or {}

	if vim.api.nvim_win_is_valid(win) then
		self:close_window()
		return
	end

	if not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true) -- scratch buffer!
	end

	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "minipoon"
	vim.bo[buf].buftype = "acwrite"

	if vim.api.nvim_buf_get_name(buf) == "" then
		vim.api.nvim_buf_set_name(buf, get_menu_name())
	end

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = augroup,
		buffer = buf,
		callback = function()
			local entries = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			vim.schedule(function()
				self:_update_marks(entries)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = buf,
		callback = function()
			local entries = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			vim.schedule(function()
				self:_update_marks(entries)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("QuitPre", {
		group = augroup,
		callback = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
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
		title = " minipoon ",
		title_pos = "center",
		border = "rounded",
	}

	local contents = self:_get_mark_names()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, contents)

	win_config = vim.tbl_deep_extend("force", win_config, default_opts)
	local win = vim.api.nvim_open_win(buf, true, win_config)
	window = { buf = buf, win = win }
end

local marks = Marks:new()

vim.api.nvim_create_autocmd("QuitPre", {
	group = augroup,
	callback = function()
		local json = vim.json.encode(marks.list)
		vim.fn.writefile({ json }, data_file)
	end,
})

vim.api.nvim_create_autocmd("DirChanged", {
	group = augroup,
	callback = function()
		marks.root = get_root()
	end,
})

return marks
