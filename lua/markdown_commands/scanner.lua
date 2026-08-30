local M = {}

local function normalize(path)
  return path:gsub("\\", "/")
end

local function is_markdown(name, extensions)
  local lower = name:lower()
  for _, extension in ipairs(extensions) do
    if lower:sub(-#extension - 1) == "." .. extension:lower() then
      return true
    end
  end
  return false
end

local function is_excluded(relative_path, exclusions)
  relative_path = normalize(relative_path):gsub("^%./", "")
  for _, exclusion in ipairs(exclusions) do
    local candidate = normalize(exclusion):gsub("^%./", ""):gsub("/$", "")
    if
      relative_path == candidate
      or relative_path:sub(1, #candidate + 1) == candidate .. "/"
      or relative_path:find("/" .. vim.pesc(candidate) .. "/", 1, false)
    then
      return true
    end
  end
  return false
end

local function is_configured(relative_path, configured_paths)
  relative_path = normalize(relative_path):gsub("^%./", "")
  for _, configured_path in ipairs(configured_paths) do
    local candidate = normalize(configured_path):gsub("^%./", ""):gsub("/$", "")
    if
      candidate == "."
      or candidate == ""
      or relative_path == candidate
      or relative_path:sub(1, #candidate + 1) == candidate .. "/"
    then
      return true
    end
  end
  return false
end

local function git_markdown_files(root, search)
  if not search.respect_gitignore then
    return nil
  end
  local git_marker = vim.uv.fs_stat(vim.fs.joinpath(root, ".git"))
  if vim.fn.executable("git") ~= 1 then
    if git_marker then
      error("markdown-commands.nvim: Git is required to respect ignore rules in this project")
    end
    return nil
  end
  local inside = vim.system({ "git", "-C", root, "rev-parse", "--is-inside-work-tree" }, { text = true }):wait()
  if inside.code ~= 0 then
    if git_marker then
      error("markdown-commands.nvim: git rev-parse failed; refusing to scan ignored files")
    end
    return nil
  end
  local result = vim
    .system({ "git", "-C", root, "ls-files", "-co", "--exclude-standard", "-z" }, { text = true })
    :wait()
  if result.code ~= 0 then
    error("markdown-commands.nvim: git ls-files failed; refusing to scan ignored files")
  end

  local files = {}
  for relative_path in (result.stdout or ""):gmatch("([^%z]+)") do
    if
      is_markdown(relative_path, search.extensions)
      and is_configured(relative_path, search.directories)
      and not is_excluded(relative_path, search.exclude)
    then
      table.insert(files, vim.fs.joinpath(root, relative_path))
    end
  end
  return files
end

local function validate_configured_paths(root, configured_paths)
  local normalized_root = normalize(vim.fs.normalize(root)):gsub("/$", "")
  for _, configured_path in ipairs(configured_paths) do
    if configured_path:match("^[/\\]") or configured_path:match("^%a:[/\\]") then
      error("markdown-commands.nvim: search paths must be relative to the project root")
    end
    local full_path = normalize(vim.fs.normalize(vim.fs.joinpath(root, configured_path)))
    if full_path ~= normalized_root and full_path:sub(1, #normalized_root + 1) ~= normalized_root .. "/" then
      error("markdown-commands.nvim: configured search path is outside the project root: " .. configured_path)
    end
  end
end

local function markdown_files(root, search)
  local git_files = git_markdown_files(root, search)
  if git_files then
    table.sort(git_files)
    return git_files
  end

  local files = {}
  local seen = {}
  local function add(path)
    path = vim.fs.normalize(path)
    local relative_path = normalize(path:sub(#root + 2))
    if not seen[path] and is_markdown(path, search.extensions) and not is_excluded(relative_path, search.exclude) then
      seen[path] = true
      table.insert(files, path)
    end
  end
  local function walk(directory)
    for name, kind in vim.fs.dir(directory) do
      local path = vim.fs.joinpath(directory, name)
      local relative_path = normalize(path:sub(#root + 2))
      if kind == "directory" and not is_excluded(relative_path, search.exclude) then
        walk(path)
      elseif kind == "file" then
        add(path)
      end
    end
  end

  for _, configured_path in ipairs(search.directories) do
    local path = vim.fs.normalize(vim.fs.joinpath(root, configured_path))
    local stat = vim.uv.fs_stat(path)
    if stat and stat.type == "directory" then
      walk(path)
    elseif stat and stat.type == "file" then
      add(path)
    end
  end

  table.sort(files)
  return files
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function opening_fence(line)
  local indent, marker, info = line:match("^( *)([`~]+)%s*([^%s]*)")
  if not marker or #indent > 3 or #marker < 3 then
    return nil
  end
  local character = marker:sub(1, 1)
  if marker ~= character:rep(#marker) then
    return nil
  end
  return {
    character = character,
    length = #marker,
    language = info:lower():gsub("^%{?%.", ""):gsub("%}?$", ""),
  }
end

local function is_closing_fence(line, opening)
  local indent, marker = line:match("^( *)([`~]+)%s*$")
  return marker ~= nil
    and #indent <= 3
    and marker:sub(1, 1) == opening.character
    and marker == opening.character:rep(#marker)
    and #marker >= opening.length
end

local function parse_file(root, path, fences)
  local lines = vim.fn.readfile(path)
  local entries = {}
  local headings = {}
  local previous_text
  local index = 1

  while index <= #lines do
    local line = lines[index]
    local hashes, heading = line:match("^(#+)%s+(.+)%s*$")
    if hashes then
      headings[#hashes] = trim(heading:gsub("%s+#+%s*$", ""))
      for level = #hashes + 1, #headings do
        headings[level] = nil
      end
      previous_text = nil
    else
      local opening = opening_fence(line)
      if opening then
        local start_line = index
        local block = {}
        index = index + 1
        while index <= #lines and not is_closing_fence(lines[index], opening) do
          table.insert(block, lines[index])
          index = index + 1
        end
        if index > #lines then
          break
        end
        if vim.tbl_contains(fences.languages, opening.language) then
          local context = {}
          for level = 1, 6 do
            if headings[level] then
              table.insert(context, headings[level])
            end
          end
          if previous_text then
            table.insert(context, (previous_text:gsub("[:%.]%s*$", "")))
          end
          local relative_path = normalize(path:sub(#root + 2))
          table.insert(entries, {
            name = #context > 0 and table.concat(context, " › ") or relative_path .. ":" .. start_line,
            command = #block > 0 and table.concat(block, "\n") .. "\n" or "",
            block = block,
            language = opening.language,
            path = path,
            relative_path = relative_path,
            start_line = start_line,
            end_line = index,
            root = root,
          })
        end
        previous_text = nil
      elseif trim(line) ~= "" then
        previous_text = trim(line)
      end
    end
    index = index + 1
  end

  return entries
end

function M.scan(opts)
  local root = vim.fs.normalize(assert(opts.root, "root is required"))
  local search = vim.tbl_deep_extend("force", {
    directories = { "." },
    extensions = { "md", "markdown" },
    exclude = { ".git", "node_modules", "vendor", "dist", "build" },
    respect_gitignore = true,
  }, opts.search or {})
  validate_configured_paths(root, search.directories)
  local fences = {
    languages = opts.fences and opts.fences.languages or { "sh", "bash", "shell", "zsh" },
  }
  local entries = {}
  for _, path in ipairs(markdown_files(root, search)) do
    vim.list_extend(entries, parse_file(root, path, fences))
  end
  return entries
end

return M
