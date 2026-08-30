# markdown-commands.nvim

Find shell commands documented anywhere in a project, choose one with Telescope, and run it in a native Neovim terminal.

The plugin treats fenced `sh`, `bash`, `shell`, and `zsh` blocks as discoverable commands. Documentation remains the source of truth: no task annotations or separate project task files are required.

## Features

- Recursively scans configurable Markdown files and directories.
- Honors `.gitignore` in Git repositories.
- Excludes dependency and build directories by default.
- Uses heading breadcrumbs and complete surrounding prose to name and explain commands.
- Shows configurable source metadata, script comments, inputs, placeholders, and operational signals in Telescope.
- Can group identical commands while retaining every Markdown source.
- Preserves multiline shell blocks exactly.
- Runs with Neovim's built-in terminal job support—Telescope is the only plugin dependency.
- Opens the source, copies the command, or edits it in a scratch buffer before running.
- Remembers and reruns the last selected command.

## Requirements

- Neovim 0.11 or newer
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- Git, if `respect_gitignore` is enabled for a Git project
- The interpreters used by the configured Markdown fence languages

## Installation

### lazy.nvim

```lua
{
  "NoNoseYaKnew/markdown-commands.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  opts = {},
  keys = {
    {
      "<leader>pc",
      "<cmd>MarkdownCommands<cr>",
      desc = "Project Markdown commands",
    },
    {
      "<leader>pC",
      "<cmd>MarkdownCommandsRunLast<cr>",
      desc = "Run last Markdown command",
    },
  },
}
```

With vim-plug:

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'NoNoseYaKnew/markdown-commands.nvim'

lua << EOF
require("markdown_commands").setup({
  terminal = {
    provider = "floaterm", -- optional: reuse vim-floaterm's popup
  },
})
EOF
```

`plenary.nvim` is Telescope's dependency; `markdown-commands.nvim` only calls Telescope directly. When using the Floaterm provider, keep the existing `Plug 'voldikss/vim-floaterm'` declaration.

For local development, use a Lazy path instead:

```lua
{
  dir = "/path/to/markdown-commands.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  opts = {},
}
```

## Usage

Run:

```vim
:MarkdownCommands
```

The picker scans the project and provides these actions:

| Mapping | Action |
|---|---|
| `<CR>` | Run the selected command |
| `<C-e>` | Edit the command in a scratch buffer; `<leader>r` runs the edited version |
| `<C-o>` | Open the command's Markdown source |
| `<C-y>` | Copy the exact command to the clipboard |

Rerun the last selected or edited command with:

```vim
:MarkdownCommandsRunLast
```

No commands run during scanning. Execution requires an explicit selection in Telescope.

## Configuration

These are the defaults:

```lua
require("markdown_commands").setup({
  search = {
    -- Entries may be directories or individual Markdown files, relative to
    -- the detected project root. "." scans the entire project.
    directories = { "." },
    extensions = { "md", "markdown" },
    exclude = {
      ".git",
      "node_modules",
      "vendor",
      "dist",
      "build",
    },
    respect_gitignore = true,
  },

  fences = {
    languages = { "sh", "bash", "shell", "zsh" },
  },

  root_markers = { ".git" },

  context = {
    before = true,       -- paragraph preceding the shell fence
    after = true,        -- paragraph following the shell fence
    comments = true,     -- comments extracted from the script
    metadata = true,     -- language, executable, lines, sources, cwd
    variables = false,   -- environment references and <placeholders>
    signals = false,     -- descriptive operational signals; not a safety verdict
    deduplicate = false, -- group identical command bodies and retain all sources
  },

  terminal = {
    -- Native Neovim is the default. Use "floaterm" to reuse vim-floaterm.
    provider = "native",
    -- Native provider only: "horizontal", "vertical", "float", or "current"
    direction = "horizontal",
    size = 15,
    start_insert = true,
    close_on_success = false,
    -- Options forwarded to vim-floaterm when provider = "floaterm".
    floaterm = {},
    shells = {
      sh = "sh",
      bash = "bash",
      shell = vim.o.shell ~= "" and vim.o.shell or "sh",
      zsh = "zsh",
    },
  },
})
```

### Rich command context

The preview can include adjacent Markdown text before and after a fence, full-line and inline shell comments, source locations, working directory, a conservative best-effort command name, line count, possible environment references, angle-bracket placeholders, and descriptive operational signals. Every category is independently configurable through `context`.

`variables`, `signals`, and `deduplicate` default to `false` because they add heuristic or grouping behavior that some users may not want. Enable the complete context model with:

```lua
require("markdown_commands").setup({
  context = {
    before = true,
    after = true,
    comments = true,
    metadata = true,
    variables = true,
    signals = true,
    deduplicate = true,
  },
})
```

Variable metadata reports names only; inline assignment values are never copied into metadata. Reference detection ignores comments, single-quoted text, and escaped dollar signs, and understands common braced forms such as `${VAR:-default}`. The raw command preview remains exact because reviewing the actual command is the plugin's purpose.

The command-name heuristic recognizes common assignment, `env`, `sudo`, and shell-wrapper prefixes. It omits the field when the first line begins with control syntax rather than pretending to identify an executable.

Signals currently identify characteristics such as `sudo`, destructive command words, force flags, interactive terminal flags, and likely long-running commands. Quoted text and shell comments are excluded. Signals are search and review hints—not a determination that a command is safe or unsafe.

When deduplication is enabled, exact command bodies using the same fence language are grouped. Every source, source-specific name, and surrounding context is retained in the preview. Source-opening actions use the first discovered source.

### Terminal providers

The default `native` provider opens a Neovim terminal without another plugin. To reuse an existing [vim-floaterm](https://github.com/voldikss/vim-floaterm) popup and its global window styling:

```lua
require("markdown_commands").setup({
  terminal = {
    provider = "floaterm",
  },
})
```

`vim-floaterm` remains optional and is not a declared runtime dependency. Per-command Floaterm options can be supplied through `terminal.floaterm`, for example `{ wintype = "float", autoclose = "never" }`.

A function can provide any other terminal integration. It receives an execution context containing `argv`, `command`, `cwd`, `entry`, `name`, `shell`, and `on_exit`:

```lua
require("markdown_commands").setup({
  terminal = {
    provider = function(context, terminal_config)
      -- Open context.argv in your terminal implementation.
      -- Call context.on_exit(exit_code) when it exits.
    end,
  },
})
```

To scan only conventional documentation locations:

```lua
require("markdown_commands").setup({
  search = {
    directories = {
      "README.md",
      "docs",
      ".github",
    },
  },
})
```

To support another shell fence, configure both discovery and its executable:

```lua
require("markdown_commands").setup({
  fences = {
    languages = { "sh", "bash", "fish" },
  },
  terminal = {
    shells = {
      fish = "fish",
    },
  },
})
```

## Command naming

Picker names are assembled from:

1. the active Markdown heading hierarchy;
2. the nearest non-empty prose line before the fence;
3. the source path and line number when no context exists.

For example:

````markdown
# Development

Start the local application:

```bash
npm run dev
```
````

appears as `Development › Start the local application`.

## Project roots and ignored files

The plugin searches upward from the current buffer for `root_markers`, then falls back to Neovim's current working directory.

Inside a Git repository, `git ls-files --cached --others --exclude-standard` supplies candidates when `respect_gitignore = true`. This includes tracked and untracked Markdown while excluding ignored files. If Git discovery fails, scanning stops rather than exposing commands from ignored files. Outside Git, the plugin recursively walks configured locations and applies `search.exclude`.

## Safety

A repository can document destructive commands. The plugin deliberately does not attempt to decide which shell commands are safe. It never runs commands automatically, and Telescope previews the exact block before execution. Use `<C-e>` when you want to remove or modify part of a command first.

Commands run from the detected project root using the executable configured for their fence language.

## Development

Clone the test dependencies into `.deps`, then run:

```sh
mkdir -p .deps
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim
git clone --depth 1 https://github.com/nvim-telescope/telescope.nvim .deps/telescope.nvim
git clone --depth 1 https://github.com/voldikss/vim-floaterm.git .deps/vim-floaterm
NVIM_BIN=nvim bash scripts/test.sh
```

The focused test commands are quiet on success and print bounded diagnostics on failure.

## License

MIT
