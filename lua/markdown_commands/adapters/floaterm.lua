local M = {}

local function safe_name(name)
  local value = name:gsub("[^%w_.-]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  return value ~= "" and value or "markdown-command"
end

function M.run(context, terminal_config)
  local floaterm_config = vim.deepcopy(terminal_config.floaterm or {})
  floaterm_config.cwd = context.cwd
  floaterm_config.name = floaterm_config.name or safe_name(context.name)

  local ok, buffer_or_error = pcall(vim.fn["floaterm#terminal#open"], -1, context.argv, {
    on_exit = function(_, exit_code)
      context.on_exit(tonumber(exit_code) or -1)
    end,
  }, floaterm_config)
  if not ok then
    error("markdown-commands.nvim: Floaterm provider failed; is vim-floaterm installed? " .. tostring(buffer_or_error))
  end
  return buffer_or_error
end

return M
