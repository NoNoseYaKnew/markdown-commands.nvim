local h = dofile("tests/helpers.lua")

h.run({
  ["setup registers commands and pick opens Telescope for discovered commands"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "# Development",
      "Run tests:",
      "```sh",
      "printf test",
      "```",
    })

    local plugin = require("markdown_commands")
    plugin.setup({ terminal = { start_insert = false } })

    h.eq(2, vim.fn.exists(":MarkdownCommands"))
    h.eq(2, vim.fn.exists(":MarkdownCommandsRunLast"))

    plugin.pick({ root = root })
    local prompt_buffer = vim.api.nvim_get_current_buf()
    h.eq("TelescopePrompt", vim.bo[prompt_buffer].filetype)
    require("telescope.actions").close(prompt_buffer)
  end,

  ["selecting a Telescope entry runs it in the native terminal"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "```sh",
      "printf selected > selected.txt",
      "```",
    })

    local plugin = require("markdown_commands")
    plugin.setup({ terminal = { direction = "current", start_insert = false } })
    plugin.pick({ root = root })

    local prompt_buffer = vim.api.nvim_get_current_buf()
    h.eq(
      true,
      vim.wait(1000, function()
        return require("telescope.actions.state").get_selected_entry() ~= nil
      end),
      "Telescope did not select an entry"
    )
    require("telescope.actions").select_default(prompt_buffer)

    h.eq(
      true,
      vim.wait(3000, function()
        return vim.uv.fs_stat(root .. "/selected.txt") ~= nil
      end),
      "selected command did not run"
    )
    h.eq({ "selected" }, vim.fn.readfile(root .. "/selected.txt"))
  end,
})
