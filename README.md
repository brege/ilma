# ilma

A project backup and archival tool with selective project-type awareness, pruning, encryption, and remote synchronization.

## Features

- **Project-Type Awareness**

  Automatic detection of and applies appropriate exclusions for Python, Node.js, LaTeX, Bash projects and can be extended to any project with build and run matter.

- **Standard GPG, tar, and rsync core with ergonomic CLI**

  GPG encryption for secure transport and storage. Create context mirrors of projects (working tree without git artifacts, node\_modules, build outputs) for LLM interaction or quick archival

- **Prune per-project build artifacts on archival**

  Can be easily configured to automatically remove disposable files and directories based on a per-project or recursive cleanup task, logging events and creating backups for recovery.

## Quick Start

**Immediate Backup**

By default, **ilma** will backup the current directory and store a copy as a sibling.

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
    --bak                  # backup to ~/dissertation.bak
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
> The default compression library used in this project is [Zstandard (`zstd`)](https://github.com/facebook/zstd). This is a personal choice, which I use because of good performance on Btrfs filesystems.  Zstandard is also [the algorithm restic uses](https://restic.readthedocs.io/en/latest/100_references.html). While `zstd` is not yet as widely supported across all platforms as `gzip`, `bzip2`, or `xz` (in that order), it is available on most modern Linux systems.
>
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
See **[`configs/local/dot-ilma.conf.example`](./configs/local/dot-ilma.conf.example)** for a kitchen sink example.

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
ilma -a --verify                 # Archive and verify contents
ilma -e --verify --remote srv:/dst  # Encrypt, upload, and verify remote hash
```

### Analysis & Statistics

Create context mirrors for LLM interaction by excluding git history, build artifacts, and dependency directories. Snapshots current working state including uncommitted and untracked files without git ceremony.

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
ilma validate --full             # Includes remote + dependency checks
ilma validate --remote           # Remote connectivity + manifest linting
```

### Configuration

Output your current configuration at any time, in or outside of a project.

```bash
ilma config [PROJECT_PATH]       # Show resolved configuration
```

### Archive Management

GPG encryption for secure transport to untrusted or exposed storage.
Extract and decrypt commands auto-detect compression formats and use chunked processing for efficiency.

```bash
ilma extract archive.tar.zst     # Auto-detects compression format
ilma decrypt file.tar.zst.gpg    # Decrypts and decompresses in one pass
```

---

## What ilma is and is not

You use **ilma** to backup irreplaceable things like configs, databases, pictures, presentations, etc.
You use **ilma** to quickly create archives from local and remote work, take them on the go securely, 
and recover them when needed.

**ilma** is **NOT** intended to be a deduplication or synchronization tool.
These tools offer better coverage for those tasks:

- Recommended encrypted, deduplicated backups: [**restic**](https://restic.net/)
- Recommended synchronization tool: [**syncthing**](https://syncthing.net/)

Because **ilma** is written as a shell wrapper for common file-handling tools,
ilma-"generated" files are completely recoverable without needing ilma.
Restic requires restic for recovery.
Syncthing is synchronous, and opaque in the only place you get encryption: "untrusted device" mode.

**ilma** works in addition to restic and syncthing for different purposes.
Restic efficiently backs up entire home directories with deduplication and versioning.
Syncthing maintains synchronized state across devices.
ilma can be used to create encrypted project snapshots for transport to untrusted storage.

Since ilma can push to multiple destinations, additional encrypted archives can be placed in syncthing folders or backed up by restic alongside other data.

### Backing up remote configs, databases, etc

Pull from remote machines (NAS, Raspberry Pi, servers) without running an SSH server on your local machine.
Job manifests use rsync's filter syntax for selective transfer.

```bash
ilma remote pull --job admin@server.ini
```

The `--job` file is a manifest that can be made as exclusive or inclusive as you want. It **is** better to be as exclusive as you can here. An example:
```ini
[job]
id=admin@server.ini
...
[manifest]
+ .          # sync all non-hidden files in /home/admin
- .*         # ignore all hidden files in /home/admin
...
+ .config/** # but DO sync .config/
...
+ .ssh/**    # and sync .ssh/
...
```


## License

[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html)

## Development

See [`lib/index.md`](./lib/index.md).
