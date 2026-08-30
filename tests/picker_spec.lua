local h = dofile("tests/helpers.lua")

local entry = {
  name = "Development › Start API",
  language = "bash",
  executable = "uv",
  line_count = 2,
  relative_path = "docs/development.md",
  start_line = 10,
  end_line = 13,
  root = "/project",
  sources = {
    {
      relative_path = "docs/development.md",
      start_line = 10,
      end_line = 13,
      name = "Development source",
      context = { before = { "Primary source context" } },
    },
    {
      relative_path = "README.md",
      start_line = 30,
      end_line = 33,
      name = "README source",
      context = { before = { "Secondary source context" } },
    },
  },
  context = {
    before = { "Starts the API.", "Requires PostgreSQL." },
    after = { "Wait for the health check." },
    comments = { "Use hot reload" },
    inline_environment = { "PORT" },
    referenced_environment = { "ENVIRONMENT" },
    placeholders = { "version" },
    signals = { "long-running" },
  },
  block = { "# Use hot reload", "PORT=8080 uv run server --reload" },
  command = "# Use hot reload\nPORT=8080 uv run server --reload\n",
  search_command = "PORT=8080 uv run server --reload",
}

h.run({
  ["preview renders enabled rich context"] = function()
    local lines = require("markdown_commands.picker").preview_lines(entry, {
      before = true,
      after = true,
      comments = true,
      variables = true,
      signals = true,
      metadata = true,
    })
    local preview = table.concat(lines, "\n")

    h.eq(true, preview:find("# bash · uv · 2 lines", 1, true) ~= nil)
    h.eq(true, preview:find("# Sources (2)", 1, true) ~= nil)
    h.eq(true, preview:find("# Before\n# Starts the API.\n# Requires PostgreSQL.", 1, true) ~= nil)
    h.eq(true, preview:find("# Script comments\n# Use hot reload", 1, true) ~= nil)
    h.eq(true, preview:find("# Inputs\n# Inline environment: PORT", 1, true) ~= nil)
    h.eq(true, preview:find("Primary source context", 1, true) ~= nil)
    h.eq(true, preview:find("Secondary source context", 1, true) ~= nil)
    h.eq(true, preview:find("# Signals: long-running", 1, true) ~= nil)
    h.eq(true, preview:find("# After running\n# Wait for the health check.", 1, true) ~= nil)
    h.eq(true, preview:find("PORT=8080 uv run server --reload", 1, true) ~= nil)
  end,

  ["preview omits disabled optional sections"] = function()
    local lines = require("markdown_commands.picker").preview_lines(entry, {
      before = false,
      after = false,
      comments = false,
      variables = false,
      signals = false,
      metadata = false,
    })
    local preview = table.concat(lines, "\n")

    h.eq(true, preview:find("Sources", 1, true) ~= nil)
    h.eq(false, preview:find("Primary source context", 1, true) ~= nil)
    h.eq(false, preview:find("Before", 1, true) ~= nil)
    h.eq(false, preview:find("Inputs", 1, true) ~= nil)
    h.eq(false, preview:find("Signals", 1, true) ~= nil)
    h.eq(true, preview:find("PORT=8080 uv run server --reload", 1, true) ~= nil)
  end,

  ["ordinal includes only enabled context categories"] = function()
    local picker = require("markdown_commands.picker")
    local hidden = picker.ordinal(entry, {
      before = false,
      after = false,
      comments = false,
      variables = false,
      signals = false,
      metadata = false,
    })
    h.eq(false, hidden:find("Requires PostgreSQL", 1, true) ~= nil)
    h.eq(false, hidden:find("Use hot reload", 1, true) ~= nil)
    h.eq(false, hidden:find("long-running", 1, true) ~= nil)

    local visible = picker.ordinal(entry, { before = true, signals = true })
    h.eq(true, visible:find("Requires PostgreSQL", 1, true) ~= nil)
    h.eq(true, visible:find("long-running", 1, true) ~= nil)
  end,
})
