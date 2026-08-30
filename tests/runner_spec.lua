local h = dofile("tests/helpers.lua")

h.run({
  ["run executes the exact multiline script from the project root"] = function()
    local root = h.tempdir()
    local output = root .. "/result.txt"
    local plugin = require("markdown_commands")
    plugin.setup({
      terminal = {
        direction = "current",
        start_insert = false,
      },
    })

    local job_id = plugin.run({
      name = "Write result",
      command = table.concat({
        "value='hello world'",
        'if [ -n "$value" ]; then',
        "  printf '%s' \"$value\" > result.txt",
        "fi",
      }, "\n"),
      language = "bash",
      root = root,
      relative_path = "README.md",
      start_line = 1,
    })

    h.eq("number", type(job_id))
    local completed = vim.wait(3000, function()
      return vim.uv.fs_stat(output) ~= nil and vim.deep_equal(vim.fn.readfile(output), { "hello world" })
    end, 20)
    h.eq(true, completed, "command did not create its output")
    h.eq({ "hello world" }, vim.fn.readfile(output))
  end,

  ["run delegates to a configured terminal provider"] = function()
    local captured
    local plugin = require("markdown_commands")
    plugin.setup({
      terminal = {
        provider = function(context)
          captured = context
          return 77
        end,
      },
    })

    local result = plugin.run({
      name = "Provider command",
      command = "printf provider",
      language = "bash",
      root = "/tmp/provider-project",
    })

    h.eq(77, result)
    h.eq({ "bash", "-c", "printf provider" }, captured.argv)
    h.eq("/tmp/provider-project", captured.cwd)
    h.eq("Provider command", captured.name)
  end,

  ["Floaterm provider executes commands in a Floaterm terminal"] = function()
    local root = h.tempdir()
    local plugin = require("markdown_commands")
    plugin.setup({
      terminal = {
        provider = "floaterm",
        start_insert = false,
      },
    })

    local buffer = plugin.run({
      name = "Floaterm command",
      command = "printf popup > floaterm-result.txt",
      language = "sh",
      root = root,
    })

    h.eq("floaterm", vim.bo[buffer].filetype)
    h.eq(
      true,
      vim.wait(3000, function()
        return vim.uv.fs_stat(root .. "/floaterm-result.txt") ~= nil
      end),
      "Floaterm command did not run"
    )
    h.eq({ "popup" }, vim.fn.readfile(root .. "/floaterm-result.txt"))
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end,

  ["native provider rejects non-numeric terminal sizes without executing Ex commands"] = function()
    vim.g.markdown_commands_injected = nil
    local plugin = require("markdown_commands")
    plugin.setup({
      terminal = {
        provider = "native",
        direction = "horizontal",
        size = "1 | let g:markdown_commands_injected = 1",
        start_insert = false,
      },
    })

    local ok = pcall(plugin.run, {
      name = "Invalid size",
      command = "printf safe",
      language = "sh",
      root = h.tempdir(),
    })

    h.eq(false, ok)
    h.eq(nil, vim.g.markdown_commands_injected)
  end,
})
