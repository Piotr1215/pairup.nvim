# pairup.nvim

**Real-time AI pair programming for Neovim**

## Features

- Git diff streaming
- Virtual text overlays
- RPC control

## Installation

```lua
{
  "Piotr1215/pairup.nvim",
  config = function()
    require("pairup").setup({})
  end,
}
```

## Usage

Start with `:PairupStart`

## License

MIT

-- CLAUDE:MARKERS:START --
CLAUDE:MARKER-1,1 | Add emoji and emphasis
# 🚀 pairup.nvim
CLAUDE:MARKER-3,1 | Make description more compelling
**🤖 Real-time AI pair programming for Neovim - Transform your coding workflow**
CLAUDE:MARKER-5,1 | Add emoji to Features heading
## ✨ Features
CLAUDE:MARKER-7,3 | Enhance feature list with emojis and descriptions
- 🔥 **Git diff streaming** - Automatic context awareness
- 💡 **Virtual text overlays** - Review before accepting
- 🎯 **RPC control** - Direct Neovim manipulation
CLAUDE:MARKER-10,1 | Add zero config feature replacing empty line
- 🚀 **Zero config** - Works out of the box

CLAUDE:MARKER-11,1 | Add emoji to Installation heading
## 📦 Installation
CLAUDE:MARKER-12,0 | Add installation section header

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)
CLAUDE:MARKER-13,8 | Enhance installation example

```lua
{
  "Piotr1215/pairup.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("pairup").setup({
      -- Your config here
    })
  end,
  keys = {
    { "<leader>cs", "<cmd>PairupStart<cr>", desc = "Start AI" },
  },
}
```
CLAUDE:MARKER-22,1 | Add emoji to Usage heading
## 🎮 Usage
CLAUDE:MARKER-24,1 | Enhance usage section
```vim
" Start AI assistant
:PairupStart

" Send context
:PairupContext

" Accept overlay
:PairAccept
```

See [documentation](https://github.com/Piotr1215/pairup.nvim) for more.
CLAUDE:MARKER-25,0 | Add contributing section

## 🤝 Contributing

Contributions welcome! Please read our [contributing guide](CONTRIBUTING.md).

CLAUDE:MARKER-26,1 | Add emoji to License heading
## 📄 License
CLAUDE:MARKER-28,1 | Enhance license line
MIT © 2024 Piotr1215
CLAUDE:MARKER-29,0 | Add footer decoration

---

<div align="center">
Made with ❤️ for Neovim
</div>
-- CLAUDE:MARKERS:END --