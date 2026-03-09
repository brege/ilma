## Changelog

### 2026-03-09

- Remove console, scan, and prune from ilma
- Move project litter review into dil
- Narrow ilma back to backup, archive, encrypt, extract, and remote pull

### 2025-12-26

- Add --type flag to console command for project type statistics
- Add TypeScript and ES module file types to Node.js schema
- Warn when local .ilma.conf overrides --type flag
- Reformat shell scripts with shfmt for consistency
- Update pre-commit hooks to maintained repositories

### 2025-12-12

- Fix scan/prune clause building
- Improve verbose labels in template output
- Remove --context backups from backup options
- Refactor command harness extraction

### 2025-12-11

- Ensure context mirror generation works with known types
- Fix context mirror generation to create as sibling directory
- Add defensive null project root handling
- Add GitHub Actions test workflow
- Add comprehensive test suite and unit tests
- Add smoke test ensemble

### 2025-12-09

- Document future refactoring plans

### 2025-12-05

- Update help text

### 2025-11-22

- Centralize tar options configuration

### 2025-11-13

- Add --timestamp flag for retroactive and override file touches
- Install only changed components on update

### 2025-11-09

- Improve messaging for install process

### 2025-11-06

- Add install script for system-wide deployment

### 2025-10-30

- Refine rsync arguments for safer, less verbose output

### 2025-10-25

- Adopt XDG config location with lookup order precedence
- Combine filter rules and jobs into single device manifest

### 2025-10-09

- Simplify .ilma.conf prefix syntax
- Implement remote pulling from manifests

### 2025-09-24

- Ensure --remote respects timestamps in basenames

### 2025-09-22

- Add --verify flag for archive and encryption integrity validation
- Add pre-flight checks for tar extraction (reject absolute paths and .. entries)
- Add configurable naming, deduped paths, and GPG polish
- Add remote hash verification with BSD/macOS fallbacks
- Support per-project VERIFY configuration
- Add socket and symlink guards in cleanup operations

### 2025-09-18

- Repair multi-target regression
- Add initial changelog

### 2025-09-12

- Add filesystem detection for local mirror optimization
- Restore mirror progress reporting and compression statistics
- Add multi-type and pattern support to scan and prune commands
- Add safety improvements (exclude .git and VCS paths from deletion)

### 2025-09-07

- Implement tar to GPG pipeline to eliminate temporary files

### 2025-09-06

- Add short flags (-a, -b, -c, -e, -r)
- Implement single file backup and encryption
- Implement multi-origin archive creation from multiple paths
- Add --basename for custom output filenames
- Add --target for custom output directories
- Clean up rsync output verbosity
- Fix multi-origin argument handling

### 2025-09-04

- Reorganize utilities and improve help texts

### 2025-09-03

- Merge duplicate validation logic
- Reorganize scripts with explicit --backup flag

### 2025-09-02

- Partition backup and extraction methods
- Add system and config validation with smoketests

### 2025-09-01

- Partition compression, GPG, rsync, extract, and decrypt into modular dependencies
- Implement standalone archival with GPG encryption and rsync support
- Improve atomic configuration with --type inheritance

### 2025-08-30

- Implement prune command for removing project build artifacts
- Add filesystem cruft scanning
- Ensure console stat consistency
- Add comprehensive help system
- Add trailing whitespace removal to pre-commit hooks

### 2025-08-29

- Modularize ilma into orchestrator architecture
- Resolve target location bugs in core archival
- Add project management utilities
- Add GPLv3 license

### 2025-08-23

- Initial commit
