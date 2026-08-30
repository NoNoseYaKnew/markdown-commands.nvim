local M = {}

function M.detect(markers, bufnr)
  bufnr = bufnr or 0
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  local start = buffer_path ~= "" and buffer_path or vim.uv.cwd()
  local root = vim.fs.root(start, markers)
  return vim.fs.normalize(root or vim.uv.cwd())
end

return M
