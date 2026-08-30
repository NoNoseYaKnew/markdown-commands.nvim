vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.deps/plenary.nvim")
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.deps/telescope.nvim")
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/.deps/vim-floaterm")
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
