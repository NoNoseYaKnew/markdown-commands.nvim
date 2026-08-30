local M = {}

local defaults = {
  search = {
    directories = { "." },
    extensions = { "md", "markdown" },
    exclude = { ".git", "node_modules", "vendor", "dist", "build" },
    respect_gitignore = true,
  },
  fences = {
    languages = { "sh", "bash", "shell", "zsh" },
  },
  root_markers = { ".git" },
  terminal = {
    provider = "native",
    direction = "horizontal",
    size = 15,
    start_insert = true,
    close_on_success = false,
    floaterm = {},
    shells = {
      sh = "sh",
      bash = "bash",
      shell = vim.o.shell ~= "" and vim.o.shell or "sh",
      zsh = "zsh",
    },
  },
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.values
end

return M
