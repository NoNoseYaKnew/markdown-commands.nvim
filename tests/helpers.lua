local M = {}

function M.tempdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

function M.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual:   " .. vim.inspect(actual)
    )
  end
end

function M.run(tests)
  local failures = {}
  for name, test in pairs(tests) do
    local ok, err = xpcall(test, debug.traceback)
    if not ok then
      table.insert(failures, "FAIL " .. name .. "\n" .. err)
    end
  end
  if #failures > 0 then
    vim.api.nvim_err_writeln(table.concat(failures, "\n\n"))
    vim.cmd("cquit 1")
  end
end

return M
