# Plugin Logic Simplification (v4.0)

## Summary

Replaced overlay system with streamlined implementation inspired by sidekick.nvim.

## Architecture Changes

### Before

The previous architecture used a state machine approach:

- **Extmark-based indexing**: Each suggestion tracked by Neovim extmark ID, requiring synchronization as lines shifted
- **4-state workflow**: Pending, accepted, rejected, edited states with complex transitions
- **Variant management**: Multiple alternatives per location with cycling logic
- **Position tracking**: Continuous recalculation as buffer content changed

This created tight coupling between display state and buffer state.

### After

The new architecture uses a stateless, functional approach:

- **Self-contained data**: Each overlay carries all information needed for rendering
- **Clear-and-rebuild pattern**: Full redraw on any change eliminates synchronization bugs
- **Line-based lookups**: Direct addressing without extmark indirection
- **Immediate actions**: Accept or reject happens instantly, no intermediate states

**Components**:
1. **Marker Parser** - Detects Claude's output markers in terminal
2. **Overlay Store** - Flat list of overlay objects
3. **Renderer** - Converts overlays to virtual text/lines
4. **Action Handler** - Applies or discards overlays

This separation allows each component to be tested and reasoned about independently.

## Migration Notes

If you were using removed features:
- **Staging**: Accept/reject immediately instead of marking
- **Variants**: Claude provides single best suggestion
- **Follow mode**: Manually navigate with `:PairNext`/:PairPrev`
- **Editing**: Accept and manually edit, or reject and ask for new suggestion
