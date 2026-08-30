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

local function sorted_values(values)
  local result = {}
  for value in pairs(values) do
    table.insert(result, value)
  end
  table.sort(result)
  return result
end

local function is_context_boundary(line)
  local value = trim(line)
  if value == "" then
    return false
  end
  if value:match("^#+%s+") or opening_fence(line) or value:match("^|") then
    return true
  end
  if value:match("^<[%a!/].*>$") then
    return true
  end
  local compact = value:gsub("%s", "")
  local character = compact:sub(1, 1)
  return #compact >= 3
    and (character == "-" or character == "*" or character == "_")
    and compact == character:rep(#compact)
end

local function following_paragraph(lines, closing_line)
  local paragraph = {}
  local started = false
  for index = closing_line + 1, #lines do
    local line = trim(lines[index])
    if line == "" then
      if started then
        break
      end
    elseif is_context_boundary(lines[index]) then
      break
    else
      started = true
      table.insert(paragraph, line)
    end
  end
  return paragraph
end

local function split_shell_comment(line)
  local quote
  local escaped = false
  for index = 1, #line do
    local character = line:sub(index, index)
    if escaped then
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      escaped = true
    elseif quote then
      if character == quote then
        quote = nil
      end
    elseif character == "'" or character == '"' then
      quote = character
    elseif character == "#" and (index == 1 or line:sub(index - 1, index - 1):match("[%s;|&()]")) then
      if index == 1 and line:sub(2, 2) == "!" then
        return "", nil
      end
      return line:sub(1, index - 1), trim(line:sub(index + 1))
    end
  end
  return line, nil
end

local function mask_quoted(code)
  local result = {}
  local quote
  local escaped = false
  for index = 1, #code do
    local character = code:sub(index, index)
    if escaped then
      table.insert(result, quote and " " or character)
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      table.insert(result, quote and " " or character)
      escaped = true
    elseif quote then
      table.insert(result, " ")
      if character == quote then
        quote = nil
      end
    elseif character == "'" or character == '"' then
      quote = character
      table.insert(result, " ")
    else
      table.insert(result, character)
    end
  end
  return table.concat(result)
end

local function shell_words(code)
  local words = {}
  local current = {}
  local quote
  local escaped = false
  local function finish()
    if #current > 0 then
      table.insert(words, table.concat(current))
      current = {}
    end
  end
  for index = 1, #code do
    local character = code:sub(index, index)
    if escaped then
      table.insert(current, character)
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      escaped = true
    elseif quote then
      if character == quote then
        quote = nil
      else
        table.insert(current, character)
      end
    elseif character == "'" or character == '"' then
      quote = character
    elseif character:match("%s") then
      finish()
    elseif character:match("[;|&()]") then
      finish()
      table.insert(words, character)
    else
      table.insert(current, character)
    end
  end
  finish()
  return words
end

local function executable_from(block)
  local control = {
    ["!"] = true,
    ["("] = true,
    ["{"] = true,
    case = true,
    ["do"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["then"] = true,
    ["until"] = true,
    ["while"] = true,
  }
  local sudo_value_options = { ["-u"] = true, ["--user"] = true, ["-g"] = true, ["--group"] = true }

  for _, line in ipairs(block) do
    local code = trim((split_shell_comment(line)))
    if code ~= "" then
      local words = shell_words(code)
      local index = 1
      while words[index] and words[index]:match("^[%a_][%w_]*=") do
        index = index + 1
      end
      if control[words[index]] then
        return nil
      end
      if words[index] == "env" then
        index = index + 1
        while words[index] and (words[index]:match("^%-") or words[index]:match("^[%a_][%w_]*=")) do
          index = index + 1
        end
      end
      if words[index] == "sudo" then
        index = index + 1
        while words[index] and words[index]:match("^%-") do
          local option = words[index]
          index = index + 1
          if sudo_value_options[option] and words[index] then
            index = index + 1
          end
        end
      end
      if
        words[index] == "command"
        or words[index] == "builtin"
        or words[index] == "exec"
        or words[index] == "nohup"
      then
        index = index + 1
        if words[index] and words[index]:match("^%-") then
          return nil
        end
      end
      local executable = words[index]
      if executable and not control[executable] and not executable:match("^[;|&()]$") then
        return executable
      end
    end
  end
  return nil
end

local function extract_references(code, referenced)
  code = code:gsub("'[^']*'", "")
  local quote
  local escaped = false
  local index = 1
  while index <= #code do
    local character = code:sub(index, index)
    if escaped then
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      escaped = true
    elseif quote == "'" then
      if character == "'" then
        quote = nil
      end
    elseif character == "'" and quote == nil then
      quote = "'"
    elseif character == '"' then
      quote = quote == '"' and nil or (quote == nil and '"' or quote)
    elseif character == "$" then
      if code:sub(index + 1, index + 1) == "{" then
        local closing = code:find("}", index + 2, true)
        if closing then
          local expression = code:sub(index + 2, closing - 1):gsub("^[!#]", "")
          local name = expression:match("^([%a_][%w_]*)")
          if name then
            referenced[name] = true
          end
          index = closing
        end
      else
        local name = code:sub(index + 1):match("^([%a_][%w_]*)")
        if name then
          referenced[name] = true
          index = index + #name
        end
      end
    end
    index = index + 1
  end
end

local function searchable_command(block)
  local lines = {}
  for _, line in ipairs(block) do
    local code = split_shell_comment(line)
    if trim(code) ~= "" then
      table.insert(lines, code)
    end
  end
  return table.concat(lines, "\n")
end

local function extract_command_context(block, lines, closing_line, before, options)
  local context = {}
  local code_lines = {}
  local signal_lines = {}
  local comments = {}
  for _, line in ipairs(block) do
    local code, comment = split_shell_comment(line)
    if trim(code) ~= "" then
      table.insert(code_lines, code)
      table.insert(signal_lines, mask_quoted(code))
    end
    if comment and comment ~= "" then
      table.insert(comments, comment)
    end
  end
  local command = table.concat(code_lines, "\n")
  local signal_command = table.concat(signal_lines, "\n")

  if options.before and #before > 0 then
    context.before = vim.deepcopy(before)
  end
  if options.after then
    local after = following_paragraph(lines, closing_line)
    if #after > 0 then
      context.after = after
    end
  end
  if options.comments and #comments > 0 then
    context.comments = comments
  end

  if options.variables then
    local inline = {}
    local referenced = {}
    local placeholders = {}
    for _, code in ipairs(code_lines) do
      local words = shell_words(code)
      local index = 1
      if words[index] == "export" or words[index] == "env" then
        index = index + 1
      end
      while words[index] and words[index]:match("^[%a_][%w_]*=") do
        local name = words[index]:match("^([%a_][%w_]*)=")
        inline[name] = true
        index = index + 1
      end
      extract_references(code, referenced)
    end
    for placeholder in command:gmatch("<([%a_][%w_.-]*)>") do
      placeholders[placeholder] = true
    end
    context.inline_environment = sorted_values(inline)
    context.referenced_environment = sorted_values(referenced)
    context.placeholders = sorted_values(placeholders)
  end

  if options.signals then
    local signals = {}
    if signal_command:find("%f[%w]sudo%f[%W]") then
      signals.sudo = true
    end
    if
      signal_command:find("%f[%w]rm%f[%W]")
      or signal_command:find("%f[%w]drop%f[%W]")
      or signal_command:find("%f[%w]prune%f[%W]")
      or signal_command:find("reset%s+%-%-hard")
    then
      signals.destructive = true
    end
    if signal_command:find("%-%-force", 1, false) then
      signals.force = true
    end
    if
      signal_command:find("%-%-reload", 1, false)
      or signal_command:find("%f[%w]serve%f[%W]")
      or signal_command:find("%f[%w]watch%f[%W]")
    then
      signals["long-running"] = true
    end
    for token in signal_command:gmatch("%S+") do
      if token == "-it" or token == "-ti" or token == "--interactive" or token == "--tty" then
        signals.interactive = true
      end
    end
    context.signals = sorted_values(signals)
  end

  return context
end

local function parse_file(root, path, fences, context_options)
  local lines = vim.fn.readfile(path)
  local entries = {}
  local headings = {}
  local paragraph = {}
  local last_paragraph = {}
  local index = 1

  while index <= #lines do
    local line = lines[index]
    local hashes, heading = line:match("^(#+)%s+(.+)%s*$")
    if hashes then
      headings[#hashes] = trim(heading:gsub("%s+#+%s*$", ""))
      for level = #hashes + 1, #headings do
        headings[level] = nil
      end
      paragraph = {}
      last_paragraph = {}
    else
      local opening = opening_fence(line)
      if opening then
        local start_line = index
        local before = #paragraph > 0 and vim.deepcopy(paragraph) or vim.deepcopy(last_paragraph)
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
          local name_parts = {}
          for level = 1, 6 do
            if headings[level] then
              table.insert(name_parts, headings[level])
            end
          end
          if context_options.before and #before > 0 then
            table.insert(name_parts, (before[#before]:gsub("[:%.]%s*$", "")))
          end
          local relative_path = normalize(path:sub(#root + 2))
          local name = #name_parts > 0 and table.concat(name_parts, " › ") or relative_path .. ":" .. start_line
          local rich_context = extract_command_context(block, lines, index, before, context_options)
          local executable = executable_from(block)
          local source = {
            path = path,
            relative_path = relative_path,
            start_line = start_line,
            end_line = index,
            name = name,
            context = vim.deepcopy(rich_context),
          }
          table.insert(entries, {
            name = name,
            command = #block > 0 and table.concat(block, "\n") .. "\n" or "",
            search_command = searchable_command(block),
            block = block,
            context = rich_context,
            executable = executable,
            line_count = #block,
            sources = { source },
            language = opening.language,
            path = path,
            relative_path = relative_path,
            start_line = start_line,
            end_line = index,
            root = root,
          })
        end
        paragraph = {}
        last_paragraph = {}
      elseif is_context_boundary(line) then
        paragraph = {}
        last_paragraph = {}
      elseif trim(line) ~= "" then
        table.insert(paragraph, trim(line))
      elseif #paragraph > 0 then
        last_paragraph = paragraph
        paragraph = {}
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
  local context_options = vim.tbl_deep_extend("force", {
    before = true,
    after = true,
    comments = true,
    variables = false,
    signals = false,
    deduplicate = false,
  }, opts.context or {})
  local entries = {}
  for _, path in ipairs(markdown_files(root, search)) do
    vim.list_extend(entries, parse_file(root, path, fences, context_options))
  end
  if context_options.deduplicate then
    local grouped = {}
    local by_command = {}
    for _, entry in ipairs(entries) do
      local key = entry.language .. "\0" .. entry.command
      local existing = by_command[key]
      if existing then
        vim.list_extend(existing.sources, entry.sources)
      else
        by_command[key] = entry
        table.insert(grouped, entry)
      end
    end
    entries = grouped
  end
  return entries
end

return M
