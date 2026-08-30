local M = {}

local edit_count = 0

function M.open(entry, run)
  vim.cmd("botright new")
  local buffer = vim.api.nvim_get_current_buf()
  edit_count = edit_count + 1
  vim.api.nvim_buf_set_name(
    buffer,
    ("markdown-command-edit://%d/%s"):format(edit_count, (entry.name or "command"):gsub("[^%w_.-]+", "-"))
  )
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(entry.command, "\n", { plain = true }))
  vim.bo[buffer].filetype = entry.language == "shell" and "sh" or entry.language
  vim.bo[buffer].bufhidden = "wipe"

  vim.keymap.set("n", "<leader>r", function()
    local edited = vim.deepcopy(entry)
    edited.block = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    edited.command = table.concat(edited.block, "\n")
    vim.api.nvim_buf_delete(buffer, { force = true })
    run(edited)
  end, { buffer = buffer, desc = "Run edited Markdown command" })
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buffer, { force = true })
  end, { buffer = buffer, desc = "Discard Markdown command" })

  vim.notify("Edit the command, then press <leader>r to run it", vim.log.levels.INFO)
  return buffer
end

return M
