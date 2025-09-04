#!/bin/bash
# test/generate.sh - Generate dummy project structures for testing ilma

set -e

# Handle help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << 'EOF'
Usage: generate.sh [TARGET_DIR]

Generate dummy project structures for testing ilma functionality.

ARGUMENTS:
  TARGET_DIR    Directory where test projects will be created (default: /tmp/dummy-root)

EXAMPLES:
  ./test/generate.sh                  # Creates projects in /tmp/dummy-root
  ./test/generate.sh /tmp/my-tests    # Creates projects in /tmp/my-tests

Generated Projects:
  dummy-project-python     Python project with venv, __pycache__, etc.
  dummy-project-js         JavaScript project with .ilma.conf
  dummy-project-latex      LaTeX project with build artifacts
  dummy-project-recursive  Project configured for backup recursion testing
  dummy-project-large      Large project for performance testing
EOF
    exit 0
fi

# Default target directory
TARGET_DIR="${1:-/tmp/dummy-root}"

echo "Generating dummy project structures in: $TARGET_DIR"

# Create base directory
mkdir -p "$TARGET_DIR"

# --- Dummy Python Project ---
echo "  Creating dummy-project-python..."
PYTHON_DIR="$TARGET_DIR/dummy-project-python"
mkdir -p "$PYTHON_DIR/src"

cat > "$PYTHON_DIR/src/main.py" <<'EOF'
#!/usr/bin/env python3
"""Simple dummy Python application for testing."""

def main():
    print("Hello from dummy Python project!")
    return 0

if __name__ == "__main__":
    main()
EOF

cat > "$PYTHON_DIR/requirements.txt" <<'EOF'
requests==2.25.1
click==8.0.1
pytest==6.2.4
EOF

cat > "$PYTHON_DIR/README.md" <<'EOF'
# Dummy Python Project

This is a test project for ilma functionality.

## Usage

```bash
python src/main.py
```
EOF

# --- Dummy JavaScript/Node Project ---
echo "  Creating dummy-project-js..."
JS_DIR="$TARGET_DIR/dummy-project-js"
mkdir -p "$JS_DIR/src" "$JS_DIR/dist"

cat > "$JS_DIR/package.json" <<'EOF'
{
  "name": "dummy-project-js",
  "version": "1.0.0",
  "description": "Dummy JavaScript project for testing",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "build": "echo 'Build complete'"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "devDependencies": {
    "jest": "^27.0.0"
  }
}
EOF

cat > "$JS_DIR/src/index.js" <<'EOF'
const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from dummy JS project!');
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
EOF

cat > "$JS_DIR/.ilma.conf" <<'EOF'
# JS project configuration - archive, backup, context
EXTENSIONS=(js json md css)
BACKUP_XDG_DIRS=false
# ABC directories relative to dummy-project-*/
BACKUP_BASE_DIR="../backup"
ARCHIVE_BASE_DIR="../archive"
CONTEXT_BASE_DIR="../context"
CREATE_COMPRESSED_ARCHIVE=true
MAX_ARCHIVES=3

RSYNC_EXCLUDES+=(
    --exclude 'node_modules/'
    --exclude 'package-lock.json'
    --exclude 'dist/'
    --exclude 'build/'
    --exclude '.next/'
    --exclude 'coverage/'
)

CONTEXT_FILES=()

TREE_EXCLUDES+="|node_modules|dist|build"
EOF

# --- Dummy LaTeX Project ---
echo "  Creating dummy-project-latex..."
LATEX_DIR="$TARGET_DIR/dummy-project-latex"
mkdir -p "$LATEX_DIR/chapters" "$LATEX_DIR/images"

cat > "$LATEX_DIR/main.tex" <<'EOF'
\documentclass{article}
\usepackage[utf8]{inputenc}
\usepackage{graphicx}

\title{Dummy LaTeX Document}
\author{Test Author}
\date{\today}

\begin{document}

\maketitle

\section{Introduction}
This is a dummy LaTeX document for testing ilma functionality.

\input{chapters/chapter1}

\end{document}
EOF

cat > "$LATEX_DIR/chapters/chapter1.tex" <<'EOF'
\section{Chapter 1}
This is the first chapter of the dummy document.

Lorem ipsum dolor sit amet, consectetur adipiscing elit.
EOF

# Create some build artifacts
touch "$LATEX_DIR/main.aux" "$LATEX_DIR/main.log" "$LATEX_DIR/main.pdf"

# --- Add Python junk to dummy-project-python ---
echo "  Adding Python junk files..."
# Create __pycache__ with .pyc files
mkdir -p "$PYTHON_DIR/__pycache__" "$PYTHON_DIR/src/__pycache__"
echo "compiled bytecode" > "$PYTHON_DIR/__pycache__/main.cpython-39.pyc"
echo "compiled bytecode" > "$PYTHON_DIR/src/__pycache__/helper.cpython-39.pyc"

# Create realistic venv with nested structure like thunder-muscle
mkdir -p "$PYTHON_DIR/venv/lib/python3.13/site-packages/pip/_internal/cli/__pycache__" \
         "$PYTHON_DIR/venv/lib/python3.13/site-packages/setuptools/__pycache__" \
         "$PYTHON_DIR/venv/bin" \
         "$PYTHON_DIR/venv/include"

# Create executable files in bin
echo "#!/usr/bin/env python" > "$PYTHON_DIR/venv/bin/python"
echo "#!/usr/bin/env python" > "$PYTHON_DIR/venv/bin/pip"
chmod +x "$PYTHON_DIR/venv/bin/python" "$PYTHON_DIR/venv/bin/pip"

# Create venv config files
echo "home = /usr/bin
include-system-site-packages = false
version = 3.13.0
executable = /usr/bin/python3.13" > "$PYTHON_DIR/venv/pyvenv.cfg"

# Create deep nested package structure with many files
for i in {1..20}; do
    echo "compiled bytecode $i" > "$PYTHON_DIR/venv/lib/python3.13/site-packages/pip/_internal/cli/__pycache__/file$i.cpython-313.pyc"
    echo "setup code $i" > "$PYTHON_DIR/venv/lib/python3.13/site-packages/setuptools/__pycache__/setup$i.cpython-313.pyc"
done

# Create symlink (lib64 -> lib)
ln -sf lib "$PYTHON_DIR/venv/lib64"

# Create .pytest_cache
mkdir -p "$PYTHON_DIR/.pytest_cache/v"
echo "cache data" > "$PYTHON_DIR/.pytest_cache/README.md"
echo "pytest data" > "$PYTHON_DIR/.pytest_cache/v/cache.json"

# Create dist and build dirs
mkdir -p "$PYTHON_DIR/dist" "$PYTHON_DIR/build/lib"
echo "wheel file" > "$PYTHON_DIR/dist/package-1.0-py3-none-any.whl"
echo "build artifact" > "$PYTHON_DIR/build/lib/main.py"

# --- Dummy Project with Recursion Risk ---
echo "  Creating dummy-project-recursive..."
RECURSIVE_DIR="$TARGET_DIR/dummy-project-recursive"
mkdir -p "$RECURSIVE_DIR/src"

cat > "$RECURSIVE_DIR/app.py" <<'EOF'
print("Recursive risk test project")
EOF

cat > "$RECURSIVE_DIR/.ilma.conf" <<'EOF'
# Recursive test project - backup inside project
EXTENSIONS=(py txt md)
BACKUP_XDG_DIRS=false
BACKUP_BASE_DIR="."
CREATE_COMPRESSED_ARCHIVE=false

RSYNC_EXCLUDES+=(
    --exclude '__pycache__/'
    --exclude '*.pyc'
    --exclude 'venv/'
)

CONTEXT_FILES=()
TREE_EXCLUDES+="|__pycache__|venv"
EOF

# --- Large Project for Console Hanging Test ---
echo "  Creating dummy-project-large..."
LARGE_DIR="$TARGET_DIR/dummy-project-large"
mkdir -p "$LARGE_DIR/data" "$LARGE_DIR/logs"

# Create many small files
for i in {1..100}; do
    echo "Data file $i with some content" > "$LARGE_DIR/data/file$i.txt"
done

# Create some large log files (but not too large for testing)
for i in {1..5}; do
    yes "Log entry $(date)" | head -n 1000 > "$LARGE_DIR/logs/app$i.log"
done

cat > "$LARGE_DIR/process.py" <<'EOF'
#!/usr/bin/env python3
"""Process large datasets"""
import os

def process_files():
    data_dir = "data"
    for filename in os.listdir(data_dir):
        if filename.endswith('.txt'):
            print(f"Processing {filename}")

if __name__ == "__main__":
    process_files()
EOF

echo
echo "✔ Dummy project structures generated successfully in: $TARGET_DIR"
echo
echo "Projects created:"
echo "  • dummy-project-python    - Simple Python project (no config)"
echo "  • dummy-project-js        - JavaScript/Node project (with .ilma.conf)"
echo "  • dummy-project-latex     - LaTeX project with build artifacts"
echo "  • dummy-project-recursive - Project with backup recursion risk"
echo "  • dummy-project-large     - Large project for console testing"
echo
echo "Usage examples:"
echo "  ilma $TARGET_DIR/dummy-project-python --type python"
echo "  ilma $TARGET_DIR/dummy-project-js"
echo "  ilma $TARGET_DIR/dummy-project-recursive"
echo "  ilma console $TARGET_DIR/dummy-project-large"
