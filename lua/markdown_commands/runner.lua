local M = {
  last_entry = nil,
}

local terminal_count = 0

local function split_size(config, vertical)
  local size = config.size
  if type(size) ~= "number" or size ~= math.floor(size) or size < 1 then
    error("markdown-commands.nvim: terminal.size must be a positive integer")
  end
  local maximum = vertical and math.max(vim.o.columns - 1, 1) or math.max(vim.o.lines - 2, 1)
  return math.min(size, maximum)
end

local function open_terminal(config, name)
  if config.direction == "current" then
    vim.cmd("enew")
  elseif config.direction == "vertical" then
    vim.cmd("botright vnew")
    vim.api.nvim_win_set_width(0, split_size(config, true))
  elseif config.direction == "float" then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(buffer, true, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
    })
  else
    vim.cmd("botright new")
    vim.api.nvim_win_set_height(0, split_size(config, false))
  end

  local buffer = vim.api.nvim_get_current_buf()
  vim.bo[buffer].bufhidden = "wipe"
  terminal_count = terminal_count + 1
  pcall(
    vim.api.nvim_buf_set_name,
    buffer,
    ("markdown-command://%d/%s"):format(terminal_count, name:gsub("[^%w_.-]+", "-"))
  )
  return buffer
end

local function notify_failure(entry, exit_code)
  if exit_code ~= 0 then
    vim.schedule(function()
      vim.notify(
        ("Markdown command exited with code %d: %s"):format(exit_code, entry.name or entry.command),
        vim.log.levels.ERROR
      )
    end)
  end
end

function M.run(entry, config)
  assert(type(entry) == "table", "entry is required")
  assert(type(entry.command) == "string", "entry.command is required")
  local shell = config.shells[entry.language] or entry.language or config.shells.shell
  if vim.fn.executable(shell) ~= 1 then
    error(("markdown-commands.nvim: shell executable not found: %s"):format(shell))
  end

  M.last_entry = vim.deepcopy(entry)
  local context = {
    argv = { shell, "-c", entry.command },
    command = entry.command,
    cwd = entry.root,
    entry = vim.deepcopy(entry),
    name = entry.name or "command",
    shell = shell,
    on_exit = function(exit_code)
      notify_failure(entry, exit_code)
    end,
  }
  if type(config.provider) == "function" then
    return config.provider(context, config)
  elseif config.provider == "floaterm" then
    return require("markdown_commands.adapters.floaterm").run(context, config)
  elseif config.provider ~= nil and config.provider ~= "native" then
    error("markdown-commands.nvim: unknown terminal provider: " .. tostring(config.provider))
  end

  local buffer = open_terminal(config, context.name)
  local job_id = vim.fn.jobstart(context.argv, {
    term = true,
    cwd = entry.root,
    on_exit = function(_, exit_code)
      if config.close_on_success and exit_code == 0 and vim.api.nvim_buf_is_valid(buffer) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buffer) then
            vim.api.nvim_buf_delete(buffer, { force = true })
          end
        end)
      elseif exit_code ~= 0 then
        notify_failure(entry, exit_code)
      end
    end,
  })
  if job_id <= 0 then
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    error("markdown-commands.nvim: failed to start terminal job")
  end
  if config.start_insert then
    vim.cmd("startinsert")
  end
  return job_id
end

function M.run_last(config)
  if not M.last_entry then
    vim.notify("No Markdown command has been run", vim.log.levels.WARN)
    return nil
  end
  return M.run(M.last_entry, config)
end

return M
