local M = {}

local function selected_entry()
  local selection = require("telescope.actions.state").get_selected_entry()
  return selection and selection.value or nil
end

local function open_source(entry)
  vim.cmd.edit(vim.fn.fnameescape(entry.path))
  local line_count = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.min(entry.start_line, math.max(line_count, 1)), 0 })
end

local function append_section(lines, title, values)
  if not values or #values == 0 then
    return
  end
  if #lines > 0 and lines[#lines] ~= "" then
    table.insert(lines, "#")
  end
  table.insert(lines, "# " .. title)
  for _, value in ipairs(values) do
    table.insert(lines, "# " .. value)
  end
end

local function nonempty(values)
  return values and #values > 0
end

function M.preview_lines(entry, options)
  options = options or {}
  local context = entry.context or {}
  local lines = { ("# %s"):format(entry.name) }

  if options.metadata then
    local details = { entry.language }
    if entry.executable then
      table.insert(details, entry.executable)
    end
    table.insert(
      details,
      ("%d %s"):format(entry.line_count or #entry.block, (entry.line_count or #entry.block) == 1 and "line" or "lines")
    )
    table.insert(lines, "# " .. table.concat(details, " · "))
    if not entry.sources or #entry.sources == 1 then
      table.insert(lines, ("# %s:%d-%d"):format(entry.relative_path, entry.start_line, entry.end_line))
    end
    table.insert(lines, "# cwd: " .. entry.root)
  end

  if entry.sources and #entry.sources > 1 then
    local sources = {}
    for _, source in ipairs(entry.sources) do
      table.insert(
        sources,
        ("%s:%d-%d — %s"):format(source.relative_path, source.start_line, source.end_line, source.name or "command")
      )
      local source_context = source.context or {}
      if options.before and nonempty(source_context.before) then
        table.insert(sources, "  Before: " .. table.concat(source_context.before, " "))
      end
      if options.after and nonempty(source_context.after) then
        table.insert(sources, "  After: " .. table.concat(source_context.after, " "))
      end
      if options.comments and nonempty(source_context.comments) then
        table.insert(sources, "  Comments: " .. table.concat(source_context.comments, "; "))
      end
      if options.variables then
        if nonempty(source_context.inline_environment) then
          table.insert(sources, "  Inline environment: " .. table.concat(source_context.inline_environment, ", "))
        end
        if nonempty(source_context.referenced_environment) then
          table.insert(
            sources,
            "  Referenced environment: " .. table.concat(source_context.referenced_environment, ", ")
          )
        end
        if nonempty(source_context.placeholders) then
          table.insert(sources, "  Placeholders: " .. table.concat(source_context.placeholders, ", "))
        end
      end
      if options.signals and nonempty(source_context.signals) then
        table.insert(sources, "  Signals: " .. table.concat(source_context.signals, ", "))
      end
    end
    append_section(lines, ("Sources (%d)"):format(#entry.sources), sources)
  end

  if options.before then
    append_section(lines, "Before", context.before)
  end
  if options.comments then
    append_section(lines, "Script comments", context.comments)
  end
  if options.variables then
    local inputs = {}
    if nonempty(context.inline_environment) then
      table.insert(inputs, "Inline environment: " .. table.concat(context.inline_environment, ", "))
    end
    if nonempty(context.referenced_environment) then
      table.insert(inputs, "Referenced environment: " .. table.concat(context.referenced_environment, ", "))
    end
    if nonempty(context.placeholders) then
      table.insert(inputs, "Placeholders: " .. table.concat(context.placeholders, ", "))
    end
    append_section(lines, "Inputs", inputs)
  end
  if options.signals and nonempty(context.signals) then
    if lines[#lines] ~= "" then
      table.insert(lines, "#")
    end
    table.insert(lines, "# Signals: " .. table.concat(context.signals, ", "))
  end
  if options.after then
    append_section(lines, "After running", context.after)
  end

  table.insert(lines, "")
  vim.list_extend(lines, entry.block)
  return lines
end

function M.ordinal(entry, options)
  options = options or {}
  local context = entry.context or {}
  local values = { entry.name, entry.search_command or entry.command }
  local function add(items)
    if items then
      vim.list_extend(values, items)
    end
  end

  if options.metadata then
    add({ entry.relative_path, entry.language, entry.executable or "", entry.root })
  end
  for _, source in ipairs(entry.sources or {}) do
    if options.metadata or #(entry.sources or {}) > 1 then
      add({ source.relative_path, source.name or "" })
    end
    local source_context = source.context or {}
    if options.before then
      add(source_context.before)
    end
    if options.after then
      add(source_context.after)
    end
    if options.comments then
      add(source_context.comments)
    end
    if options.variables then
      add(source_context.inline_environment)
      add(source_context.referenced_environment)
      add(source_context.placeholders)
    end
    if options.signals then
      add(source_context.signals)
    end
  end
  if options.before then
    add(context.before)
  end
  if options.after then
    add(context.after)
  end
  if options.comments then
    add(context.comments)
  end
  if options.variables then
    add(context.inline_environment)
    add(context.referenced_environment)
    add(context.placeholders)
  end
  if options.signals then
    add(context.signals)
  end
  return table.concat(values, " ")
end

local function display(entry, options)
  if not options.metadata then
    return entry.name
  end
  local details = { entry.language }
  if entry.executable then
    table.insert(details, entry.executable)
  end
  table.insert(details, (entry.line_count or #entry.block) .. "L")
  local location = entry.sources and #entry.sources > 1 and (#entry.sources .. " sources")
    or (("%s:%d"):format(entry.relative_path, entry.start_line))
  return ("%s  [%s]  %s"):format(entry.name, table.concat(details, " · "), location)
end

function M.open(entries, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local previewers = require("telescope.previewers")

  return pickers
    .new(opts.telescope or {}, {
      prompt_title = "Markdown commands",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = display(entry, opts.context or {}),
            ordinal = M.ordinal(entry, opts.context or {}),
            filename = entry.path,
            lnum = entry.start_line,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts.telescope or {}),
      previewer = previewers.new_buffer_previewer({
        title = "Shell block",
        define_preview = function(self, telescope_entry)
          local entry = telescope_entry.value
          local lines = M.preview_lines(entry, opts.context or {})
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = entry.language == "shell" and "sh" or entry.language
        end,
      }),
      attach_mappings = function(prompt_buffer, map)
        actions.select_default:replace(function()
          local entry = selected_entry()
          actions.close(prompt_buffer)
          if entry then
            opts.run(entry)
          end
        end)

        local function edit()
          local entry = selected_entry()
          actions.close(prompt_buffer)
          if entry then
            require("markdown_commands.editor").open(entry, opts.run)
          end
        end
        local function source()
          local entry = selected_entry()
          actions.close(prompt_buffer)
          if entry then
            open_source(entry)
          end
        end
        local function copy()
          local entry = selected_entry()
          if entry then
            vim.fn.setreg("+", entry.command)
            vim.notify("Copied Markdown command", vim.log.levels.INFO)
          end
        end

        map({ "i", "n" }, "<C-e>", edit)
        map({ "i", "n" }, "<C-o>", source)
        map({ "i", "n" }, "<C-y>", copy)
        return true
      end,
    })
    :find()
end

return M
