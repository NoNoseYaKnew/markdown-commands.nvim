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
          local location = ("%s:%d"):format(entry.relative_path, entry.start_line)
          return {
            value = entry,
            display = ("%s  %s"):format(entry.name, location),
            ordinal = table.concat({ entry.name, location, entry.command }, " "),
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
          local lines = {
            ("# %s"):format(entry.name),
            ("# %s:%d"):format(entry.relative_path, entry.start_line),
            ("# cwd: %s"):format(entry.root),
            "",
          }
          vim.list_extend(lines, entry.block)
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
