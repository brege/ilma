# ilma

A comprehensive project backup and archival tool with intelligent project-type awareness, encryption, and remote synchronization capabilities.

## Features

- **Project-Type Awareness**

  Automatically detects and applies appropriate exclusions for Python, Node.js, LaTeX, Bash projects and can be extended to any project with build and run matter.

- **Standard GPG, tar, and rsync core with ergonomic CLI**

  Optional file encryption for secure backup storage, quick archival and backups, context trimming repos for LLM's, secure remote push for any target type

- **Flexible and Granular Configuration**

  Global settings with per-project overrides allowing intricate customization based on many directories.

- **Prune per-project build artifacts on archival**

  Can be easily configured to automatically remove disposable files and directories based on a per-project or recursive cleanup task, logging events and creating backups for recovery.

## Quick Start

**Immediate Backup**

By default, **ilma** will backup the current directory and store a copy as a sibling directory.

```bash
ilma
```

**Prune crufty project files**

All the disposable files and directories can be easily removed with the `prune` command,
based on project type or project-local configuration files.

```bash
ilma prune ~/dissertation \
    --type latex \         # remove build artifacts .aux, .toc, etc
    --log \                # log to ~/dissertation.log
    --bak                 # backup to ~/dissertation.bak
```

**Send encrypted archive to remote server**
```bash
ilma --encrypt \
     --remote server.local:/storage/backups \
     --type latex \
     ~/dissertation
```

**Config Validation**  
```bash
ilma validate

```
**Context Overview**
```bash
ilma console 
```

## Installation

Clone the repository
```bash
git clone https://github.com/brege/ilma
cd ilma
```

Fedora dependencies
```bash
sudo dnf install rsync tree git zstd bc pv
# all compression tools (only need one)
sudo dnf install zstd gzip bzip2 xz
```

Debian/Ubuntu dependencies
```bash
sudo apt install rsync tree git zstd bc pv
sudo apt install zstd gzip bzip2 xz-utils
```

Validate dependencies
```bash
./lib/deps/deps.sh check
./lib/deps/deps.sh install-help
```

Add the **ilma** to your `$PATH`
```bash
echo 'export PATH="$PATH:/path/to/ilma"' >> ~/.bashrc
source ~/.bashrc
```

> #### Compression Algorithm Note
> This project uses [Zstandard (`zstd`)](https://github.com/facebook/zstd) as the default compression method. It offers excellent performance—especially on modern filesystems like Btrfs—and balances speed and compression efficiency better than traditional tools.
>
> While `zstd` is not yet as widely supported across all platforms as `gzip`, `bzip2`, or `xz` (in that order), it is available on most modern Linux systems. This early-stage choice reflects a focus on performance and simplicity for power users, but any of the listed tools will work just as well.
> [ [compression][1] ][ [speed][2] ][ [usage][3] ]

[1]: https://rsmith.home.xs4all.nl/miscellaneous/evaluating-zstandard-compression.html?utm_source=chatgpt.com
[2]: https://patchwork.kernel.org/project/linux-btrfs/patch/20170629194108.1674498-4-terrelln%40fb.com/?utm_source=chatgpt.com
[3]: https://thelinuxcode.com/enable-btrfs-filesystem-compression/?utm_source=chatgpt.com

### Configuration

**ilma** works out of the box with sensible defaults, but can be customized extensively.

#### Global
Copy and customize the global **`config.ini`** file
```bash
cp config.example.ini config.ini
```
#### Per-Project

Create **`.ilma.conf`** in any project for custom strategies.
See **[`configs/dot-ilma.conf.example`](./configs/dot-ilma.conf.example)** for a kitchen sink example.

---

| Supported Project Types | Common Exclusions               |
|:-----------|:---------------------------------------------|
| **python** | `__pycache__`, `venv`, `.pytest_cache`, etc. |
| **node**   | `node_modules`, `dist`, `build`, etc.        |
| **latex**  | `.aux`, `.log`, `.pdf`, etc.                 |
| **bash**   | `.log`, `.tmp`, `.out`, backup files, etc.   |

See **[`configs/`](./configs)** for common language presets.

---

## Commands

### Backup Operations
```bash
cd /path/to/project
ilma                             # Backup current directory
ilma [PROJECT_PATH]              # Backup specified directory
```

### Analysis & Statistics

This command is hand if you share your project with LLM's. 
It provides a quick overview of file and estimated token counts.

```bash
ilma console [PROJECT_PATH]      # Show detailed project statistics
ilma scan [PROJECT_PATH]         # Show files that would be excluded
ilma scan --type python --pretty # Scan with specific project type
```

### Validation & Troubleshooting

After customizing your configuration, you can validate your setup
quickly without trial-and-error on your data.

```bash
ilma validate                    # Basic configuration validation
ilma validate full               # Includes remote connectivity tests
ilma validate smoke-test         # End-to-end test with dummy project
```

### Configuration

Output your current configuration at any time, in or outside of a project.

```bash
ilma config [PROJECT_PATH]       # Show resolved configuration
```

### Archive Management

With GPG, you can encrypt your backups for secure storage,
especially useful on remote servers.

```bash
ilma extract archive.tar.zst
ilma decrypt file.tar.zst.gpg
```

## Configuration File Examples

**Simple Project Backup**

There are two main ways to make use of language-specific presets.

In **`.ilma.conf`**
```bash .ilma.conf
PROJECT_TYPE="python"
```
which is equivalent to the `ilma --type python` command.

**Encrypted Remote Backup**
```bash .ilma.conf
PROJECT_TYPE="node"
GPG_KEY_ID="your-gpg-key-id or email"
REMOTE_SERVER="server.local"
REMOTE_PATH="/storage/backups"
COMPRESSION_TYPE="zstd" 
COMPRESSION_LEVEL="3"
```

**Custom Exclusions**
```bash .ilma.conf
PROJECT_TYPE="python"
RSYNC_EXCLUDES=() # Clear default excludes
RSYNC_EXCLUDES+=(
    --exclude '*.log'
    --exclude 'tmp/'
    --exclude 'paraview/*.vtk'
)
CONTEXT_FILES+=(
    "AGENTS.md"
)
```

## Advanced Usage

### Backup Hierarchy
**ilma** creates a structured backup hierarchy:
```
project.bak/                     # Main backup directory
├── project-files/               # Complete project mirror
├── project/                     # Context mirror (key files only) 
└── project.tar.zst              # Compressed archive (if enabled)
```

### Configuration Inheritance
**ilma** uses a hierarchical configuration system:
1. **Global defaults** from `config.ini`, currently at **ilma's repo root**
2. **Project type config** (e.g., `configs/python-project.ilma.conf`) 
3. **Local overrides** from `.ilma.conf`

## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)

## Development

See [`lib/index.md`](./lib/index.md).
