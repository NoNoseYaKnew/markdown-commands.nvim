local M = {}

local config = require("markdown_commands.config")

local function replace_command(name, callback, description)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, callback, { desc = description })
end

function M.setup(opts)
  config.setup(opts)
  replace_command("MarkdownCommands", function()
    M.pick()
  end, "Find project commands in Markdown")
  replace_command("MarkdownCommandsRunLast", function()
    M.run_last()
  end, "Run the last selected Markdown command")
end

function M.scan(opts)
  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.values), opts or {})
  opts.root = opts.root or require("markdown_commands.root").detect(opts.root_markers)
  return require("markdown_commands.scanner").scan(opts)
end

function M.run(entry)
  return require("markdown_commands.runner").run(entry, config.values.terminal)
end

function M.run_last()
  return require("markdown_commands.runner").run_last(config.values.terminal)
end

function M.pick(opts)
  opts = opts or {}
  local entries = M.scan(opts)
  if #entries == 0 then
    vim.notify("No shell blocks found in project Markdown", vim.log.levels.INFO)
    return nil
  end
  return require("markdown_commands.picker").open(entries, {
    telescope = opts.telescope,
    context = vim.tbl_deep_extend("force", vim.deepcopy(config.values.context), opts.context or {}),
    run = M.run,
  })
end

return M
