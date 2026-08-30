local h = dofile("tests/helpers.lua")

h.run({
  ["scan discovers nested shell fences and preserves multiline scripts"] = function()
    local root = h.tempdir()
    h.write(root .. "/docs/development.md", {
      "# Development",
      "",
      "Start the application:",
      "",
      "```bash",
      "export MODE=development",
      'if [ -n "$MODE" ]; then',
      "  printf '%s\\n' \"$MODE\"",
      "fi",
      "```",
    })

    local entries = require("markdown_commands").scan({ root = root })

    h.eq(1, #entries)
    h.eq("Development › Start the application", entries[1].name)
    h.eq("bash", entries[1].language)
    h.eq("docs/development.md", entries[1].relative_path)
    h.eq(5, entries[1].start_line)
    h.eq(table.concat({
      "export MODE=development",
      'if [ -n "$MODE" ]; then',
      "  printf '%s\\n' \"$MODE\"",
      "fi",
    }, "\n") .. "\n", entries[1].command)
  end,

  ["scan limits discovery to configured files and directories"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", { "```sh", "echo root", "```" })
    h.write(root .. "/docs/guide.md", { "```bash", "echo docs", "```" })
    h.write(root .. "/notes/private.md", { "```sh", "echo private", "```" })

    local entries = require("markdown_commands").scan({
      root = root,
      search = { directories = { "README.md", "docs" } },
    })

    h.eq(2, #entries)
    h.eq("README.md", entries[1].relative_path)
    h.eq("docs/guide.md", entries[2].relative_path)
  end,

  ["scan respects gitignore and excluded directories"] = function()
    local root = h.tempdir()
    vim.system({ "git", "init", "-q", root }):wait()
    h.write(root .. "/.gitignore", { "docs/generated/" })
    h.write(root .. "/README.md", { "```sh", "echo visible", "```" })
    h.write(root .. "/docs/generated/api.md", { "```sh", "echo ignored", "```" })
    h.write(root .. "/node_modules/package/README.md", { "```sh", "echo dependency", "```" })

    local entries = require("markdown_commands").scan({ root = root })

    h.eq(1, #entries)
    h.eq("echo visible\n", entries[1].command)
  end,

  ["scan supports tilde fences and configurable shell languages"] = function()
    local root = h.tempdir()
    h.write(root .. "/commands.markdown", {
      "## Utilities",
      "~~~fish title=cleanup",
      "for file in *.tmp",
      "  rm -- $file",
      "end",
      "~~~~",
      "```bash",
      "echo excluded by language configuration",
      "```",
    })

    local entries = require("markdown_commands").scan({
      root = root,
      fences = { languages = { "fish" } },
    })

    h.eq(1, #entries)
    h.eq("fish", entries[1].language)
    h.eq("Utilities", entries[1].name)
    h.eq("for file in *.tmp\n  rm -- $file\nend\n", entries[1].command)
  end,

  ["scan ignores shell examples nested inside non-shell fences"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "````markdown",
      "```bash",
      "echo example only",
      "```",
      "````",
      "```bash",
      "echo runnable",
      "```",
    })

    local entries = require("markdown_commands").scan({ root = root })

    h.eq(1, #entries)
    h.eq("echo runnable\n", entries[1].command)
  end,

  ["scan allows default exclusions to be replaced"] = function()
    local root = h.tempdir()
    h.write(root .. "/node_modules/example/README.md", {
      "```sh",
      "echo included by explicit configuration",
      "```",
    })

    local entries = require("markdown_commands").scan({
      root = root,
      search = {
        exclude = {},
        respect_gitignore = false,
      },
    })

    h.eq(1, #entries)
  end,

  ["scan recognizes braced Markdown language attributes"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "```{.bash #quickstart}",
      "echo braced",
      "```",
    })

    local entries = require("markdown_commands").scan({ root = root })

    h.eq(1, #entries)
    h.eq("bash", entries[1].language)
  end,

  ["scan rejects configured paths outside the project root"] = function()
    local root = h.tempdir()
    local outside = h.tempdir()
    h.write(outside .. "/commands.md", { "```sh", "echo outside", "```" })

    local ok, message = pcall(require("markdown_commands").scan, {
      root = root,
      search = { directories = { "../" .. vim.fs.basename(outside) } },
    })

    h.eq(false, ok)
    h.eq(true, tostring(message):find("outside the project root", 1, true) ~= nil)
  end,

  ["scan fails closed when Git file discovery fails"] = function()
    local root = h.tempdir()
    local bin = h.tempdir()
    vim.fn.mkdir(root .. "/.git", "p")
    h.write(root .. "/README.md", { "```sh", "echo should not leak", "```" })
    h.write(bin .. "/git", {
      "#!/bin/sh",
      'case "$*" in',
      "  *rev-parse*) printf 'true\\n'; exit 0 ;;",
      "  *) exit 7 ;;",
      "esac",
    })
    vim.uv.fs_chmod(bin .. "/git", 493)

    local previous_path = vim.env.PATH
    vim.env.PATH = bin
    local ok, message = pcall(require("markdown_commands").scan, { root = root })
    vim.env.PATH = previous_path

    h.eq(false, ok)
    h.eq(true, tostring(message):find("git ls-files failed", 1, true) ~= nil)
  end,

  ["scan extracts rich documentation and command context"] = function()
    local root = h.tempdir()
    h.write(root .. "/docs/development.md", {
      "# Development",
      "## API",
      "Starts the API with hot reload.",
      "PostgreSQL and Redis must already be running.",
      "",
      "```bash",
      "# Launch on the documented port",
      'PORT=8080 uv run server --environment "$ENVIRONMENT" --reload',
      "docker run -it app:<version>",
      "sudo rm -rf build --force",
      "```",
      "",
      "Wait for the health check to pass.",
      "Then open the application in a browser.",
      "",
      "## Next section",
    })

    local entries = require("markdown_commands").scan({
      root = root,
      context = {
        before = true,
        after = true,
        comments = true,
        variables = true,
        signals = true,
        deduplicate = true,
      },
    })
    h.eq(1, #entries)
    local entry = entries[1]
    h.eq("Development › API › PostgreSQL and Redis must already be running", entry.name)
    h.eq({
      "Starts the API with hot reload.",
      "PostgreSQL and Redis must already be running.",
    }, entry.context.before)
    h.eq({
      "Wait for the health check to pass.",
      "Then open the application in a browser.",
    }, entry.context.after)
    h.eq({ "Launch on the documented port" }, entry.context.comments)
    h.eq({ "PORT" }, entry.context.inline_environment)
    h.eq({ "ENVIRONMENT" }, entry.context.referenced_environment)
    h.eq({ "version" }, entry.context.placeholders)
    h.eq({ "destructive", "force", "interactive", "long-running", "sudo" }, entry.context.signals)
    h.eq("uv", entry.executable)
    h.eq(4, entry.line_count)
    h.eq(1, #entry.sources)
  end,

  ["scan groups identical commands and retains every source"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", { "# Root", "Root instructions.", "```sh", "npm test", "```" })
    h.write(root .. "/docs/testing.md", { "# Testing", "Detailed testing instructions.", "```sh", "npm test", "```" })
    h.write(root .. "/z-bash.md", { "# Bash", "```bash", "npm test", "```" })

    local entries = require("markdown_commands").scan({
      root = root,
      context = { deduplicate = true },
    })

    h.eq(2, #entries)
    h.eq(2, #entries[1].sources)
    h.eq("README.md", entries[1].sources[1].relative_path)
    h.eq("docs/testing.md", entries[1].sources[2].relative_path)
    h.eq({ "Root instructions." }, entries[1].sources[1].context.before)
    h.eq({ "Detailed testing instructions." }, entries[1].sources[2].context.before)
  end,

  ["scan omits disabled optional context"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "Helpful prose.",
      "```sh",
      "# comment",
      "PORT=1 echo $VALUE --force",
      "```",
      "After prose.",
    })
    local entries = require("markdown_commands").scan({
      root = root,
      context = { before = false, after = false, comments = false, variables = false, signals = false },
    })

    h.eq({}, entries[1].context)
    h.eq(false, entries[1].name:find("Helpful prose", 1, true) ~= nil)
  end,

  ["scan extracts shell-aware comments and variable references"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "```bash",
      "#comment without space",
      "echo '# not a comment sudo rm --force' \"$EXPANDED\" '${IGNORED}' \\$ESCAPED # inline explanation",
      "echo ok;# $HIDDEN sudo rm --force",
      'echo "${WITH_DEFAULT:-x}" ${ARRAY[0]}',
      "```",
    })
    local entries = require("markdown_commands").scan({
      root = root,
      context = { comments = true, variables = true, signals = true },
    })
    h.eq(1, #entries)
    h.eq({ "comment without space", "inline explanation", "$HIDDEN sudo rm --force" }, entries[1].context.comments)
    h.eq({ "ARRAY", "EXPANDED", "WITH_DEFAULT" }, entries[1].context.referenced_environment)
    h.eq({}, entries[1].context.signals)
  end,

  ["scan reports a command only when a shell prefix can be parsed conservatively"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "```bash",
      'env PORT="hello world" sudo -u app command uv run server',
      "```",
      "```bash",
      "if ready; then run-server; fi",
      "```",
    })
    local entries = require("markdown_commands").scan({ root = root })
    h.eq("uv", entries[1].executable)
    h.eq(nil, entries[2].executable)
  end,

  ["scan does not cross Markdown structural boundaries for context"] = function()
    local root = h.tempdir()
    h.write(root .. "/README.md", {
      "Unrelated paragraph.",
      "---",
      "```sh",
      "echo bounded",
      "```",
      "| column |",
      "| --- |",
    })
    local entry = require("markdown_commands").scan({ root = root })[1]
    h.eq(nil, entry.context.before)
    h.eq(nil, entry.context.after)
  end,
})
