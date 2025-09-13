# 🚀 pairup.nvim

**🤖 Real-time AI pair programming for Neovim - Transform your coding workflow**

## ✨ Features

- 🔥 **Git diff streaming** - Automatic context awareness
- 💡 **Virtual text overlays** - Review before accepting
- 🎯 **RPC control** - Direct Neovim manipulation
- 🚀 **Zero config** - Works out of the box

## 📦 Installation


### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

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

## 🎮 Usage

```vim
" Start AI assistant
:PairupStart

" Send context
:PairupContext

" Accept overlay
:PairAccept
```

See [documentation](https://github.com/Piotr1215/pairup.nvim) for more.


## 🤝 Contributing

Contributions welcome! Please read our [contributing guide](CONTRIBUTING.md).

## 📄 License

MIT © 2024 Piotr1215

---

<div align="center">
Made with ❤️ for Neovim
</div>
