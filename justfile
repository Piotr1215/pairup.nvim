# pairup.nvim development tasks

# Show all available recipes
default:
  @just --list

# Run tests
test:
  make test

# Format code
format:
  make format

# List available diagrams
_diagrams:
  @ls diagrams/*.puml 2>/dev/null | xargs -n1 basename | sed 's/\.puml$//'

# Render PlantUML diagram as ASCII (with fzf selection if no arg)
diagram name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    echo "Available diagrams:"
    just _diagrams
    exit 1
  fi
  java -jar /usr/local/bin/plantuml.jar diagrams/$DIAGRAM.puml -txt
  cat diagrams/$DIAGRAM.atxt

# Render diagram as PNG (with fzf selection if no arg)
diagram-png name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram for PNG: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  java -jar /usr/local/bin/plantuml.jar diagrams/$DIAGRAM.puml -tpng
  echo "Created: diagrams/$DIAGRAM.png"

# Render diagram as SVG (with fzf selection if no arg)
diagram-svg name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram for SVG: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  java -jar /usr/local/bin/plantuml.jar diagrams/$DIAGRAM.puml -tsvg
  echo "Created: diagrams/$DIAGRAM.svg"

# Edit diagram in neovim (with fzf selection if no arg)
edit-diagram name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram to edit: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  nvim diagrams/$DIAGRAM.puml

# View diagram in terminal (ghostty/kitty protocol)
view-diagram name='' prompt='Press Enter to close...' watch='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram to view: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  just diagram-png $DIAGRAM
  scripts/show_image_kitty.sh diagrams/$DIAGRAM.png "" "{{prompt}}" "{{watch}}"

# Copy diagram path to clipboard (for scp download)
open-diagram name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram to download: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  just diagram-png $DIAGRAM
  FULLPATH="$(pwd)/diagrams/$DIAGRAM.png"
  echo "$FULLPATH"
  echo "Download with: scp $(whoami)@$(hostname):$FULLPATH ."

# Watch diagram and reload on save (live preview with ghostty)
watch-diagram name='':
  #!/usr/bin/env bash
  DIAGRAM="{{name}}"
  if [ -z "$DIAGRAM" ]; then
    DIAGRAM=$(just _diagrams | fzf --prompt="Select diagram to watch: " --height=10)
    [ -z "$DIAGRAM" ] && exit 0
  fi
  if [ ! -f "diagrams/$DIAGRAM.puml" ]; then
    echo "Error: diagrams/$DIAGRAM.puml not found"
    exit 1
  fi
  echo "Watching diagrams/$DIAGRAM.puml for changes..."
  echo "Edit in another terminal, save to see updates"
  echo "Press Ctrl+C to stop"
  echo ""
  echo "diagrams/$DIAGRAM.puml" | entr -rc sh -c "just view-diagram $DIAGRAM 'Watching for changes... Press Ctrl+C to quit' --watch"

# Show peripheral indicator design summary
design-summary:
  @cat design-docs/peripheral-indicator-design.md

# Show current status implementation details
status-summary:
  @cat design-docs/pairup-status-summary.md
