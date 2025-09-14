Recently I have released pairup.nvim (link to the annoucement here). Today I want to share a new feature!

CLAUDE:MARKER-1,1 | Add compelling title and hook
# [Update] pairup.nvim v2.0: AI suggestions you can review before accepting - introducing the marker overlay system

CLAUDE:MARKER-2,0 | Add context about the problem we're solving


You know that feeling when your AI assistant goes rogue and starts editing files before you can even review the changes? Or when you're copy-pasting code suggestions back and forth, losing track of what goes where?

**That's exactly what we've solved in pairup.nvim v2.0.**

CLAUDE:MARKER-2,0 | Alternative opening - more technical


## The Problem with Current AI Pair Programming

Most AI coding assistants either:
- Make direct edits to your files (scary!)
- Dump code in chat that you manually copy-paste (tedious!)
- Provide inline completions you can't properly review (risky!)

**pairup.nvim v2.0 introduces a better way: the marker-based overlay system.**

CLAUDE:MARKER-2,0 | Add main feature explanation


## What's New: Marker-Based Overlays

Instead of Claude directly editing your files, it now outputs special markers that become **reviewable overlay suggestions**:

```vim
" Claude suggests changes with markers
CLAUDE:MARKER-10,3 | Refactor with list comprehension
def process(data):
    return [item * 2 for item in data]
```

These markers transform into virtual text overlays that you can:
- 📖 Review before accepting
- 🔄 Cycle through multiple variants (Tab/Shift+Tab)
- ✅ Accept with `<leader>sa`
- ❌ Reject with `<leader>sr`

CLAUDE:MARKER-2,0 | Add demo section


## See It In Action

Here's a real example from my workflow:

1. I ask Claude to refactor a function
2. Claude adds markers to suggest changes
3. I run `:PairMarkerToOverlay`
4. Virtual overlays appear showing the suggestions
5. I press Tab to see alternative implementations
6. Accept the one I like, reject the rest

The key insight: **You maintain complete control** while still getting intelligent suggestions.

CLAUDE:MARKER-2,0 | Add technical details section

## How It Works (Technical Details)

The system uses three marker types:

- **EDIT**: Replace existing lines
- **INSERT**: Add new lines
- **DELETE**: Remove lines

Each marker includes reasoning, making Claude's thinking transparent:

```
CLAUDE:MARKER-15,5 | Simplified with list comprehension for better performance
```

The overlays persist across sessions, support multi-variant suggestions, and integrate seamlessly with your git workflow (unstaged changes = AI context).

CLAUDE:MARKER-2,0 | Add closing and links

## Try It Out

If you're already using pairup.nvim, just update to v2.0. New users can get started with:

```lua
{
  "Piotr1215/pairup.nvim",
  config = function()
    require("pairup").setup({ provider = "claude" })
  end,
}
```

**Links:**
- [GitHub Repository](https://github.com/Piotr1215/pairup.nvim)
- [Full Documentation](https://github.com/Piotr1215/pairup.nvim#readme)
- [Original Announcement](https://reddit.com/r/neovim/...) <!-- Add your original post link -->

**What do you think?** Is this approach to AI pair programming something you'd use? What features would you like to see next?

*Built for Neovim users who want AI assistance without losing control of their code.*
