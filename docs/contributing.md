# Contributing

This reference shows each command using the `ilma` entrypoint and the direct
`bash commands/<command>.sh` entrypoint. Examples assume you are in the
repository root and you have run the sandbox setup.

## Sandbox

Create a realistic fixture and a sample archive used by later examples:
```bash
tools/make-dummies.sh /tmp/ilma-dummies
export DUMMIES=/tmp/ilma-dummies
export PATH="$PWD:$PATH"
mkdir -p "$DUMMIES/artifacts"
ilma backup "$DUMMIES/dummy-project-python" --archive --target "$DUMMIES/artifacts"
ARCHIVE_PATH="$(ls -t "$DUMMIES"/artifacts/dummy-project-python-*.tar.zst | head -n 1)"
```

## Command reference

### backup
Create a backup directory (default command if you omit the subcommand).
```bash
ilma backup "$DUMMIES/dummy-project-python"
bash commands/backup.sh "$DUMMIES/dummy-project-python"
```

### config
Print the resolved configuration for a project (local config plus defaults).
```bash
ilma config "$DUMMIES/dummy-project-js"
bash commands/config.sh "$DUMMIES/dummy-project-js"
```

### console
Generate file counts, line counts, and a token estimate for a project.
```bash
ilma console "$DUMMIES/dummy-project-python" --type python
bash commands/console.sh "$DUMMIES/dummy-project-python" --type python
```

Example output:
```
Project Statistics
------------------
Metric                  Count
-----                   -----
Total files                52
.py files                   2
.md files                   2
.txt files                  1
.json files                 1
Total lines                73
.py lines                  10
.md lines                  10
.txt lines                  3
.json lines                 1
Total size (MB)             1
------------------
Source token estimate: 314 (~4 chars per token)
```
Ignores: common Python build artifacts defined in `configs/projects/python.ilma.conf`.

### scan
Show which files would be pruned for a given project type (dry-run).
```bash
ilma scan "$DUMMIES/dummy-project-python" --type python --pretty
bash commands/scan.sh "$DUMMIES/dummy-project-python" --type python --pretty
```

Example output:
```
Skip analysis for type 'python' in directory: /tmp/ilma-dummies/dummy-project-python
Dry run mode: no files will be deleted

Project directory: /tmp/ilma-dummies/dummy-project-python
  WOULD DELETE:
    /tmp/ilma-dummies/dummy-project-python/__pycache__/
    /tmp/ilma-dummies/dummy-project-python/src/__pycache__/
    /tmp/ilma-dummies/dummy-project-python/.pytest_cache/
    /tmp/ilma-dummies/dummy-project-python/venv/
    /tmp/ilma-dummies/dummy-project-python/dist/
    /tmp/ilma-dummies/dummy-project-python/build/

Dry run complete: no files deleted
```

### prune
Run the prune analysis without deleting files (add `--verbose` to list paths).
```bash
ilma prune "$DUMMIES/dummy-project-python" --type python
bash commands/prune.sh "$DUMMIES/dummy-project-python" --type python
```

### validate
Check configuration and dependency state for a project.
```bash
ilma validate "$DUMMIES/dummy-project-js"
bash commands/validate.sh "$DUMMIES/dummy-project-js"
```

### extract
Extract an archive using safe tar options (uses `ARCHIVE_PATH` from the sandbox).
```bash
ilma extract "$ARCHIVE_PATH"
bash commands/extract.sh "$ARCHIVE_PATH"
```

### decrypt
Show decrypt options and required flags (actual decrypt needs a `.gpg` archive).
```bash
ilma decrypt --help
bash commands/decrypt.sh --help
```

### remote
List discovered remote job manifests. This creates a local manifest so the list
command has something to display.
```bash
export ILMA_CONFIG_HOME="$DUMMIES/ilma-config"
mkdir -p "$ILMA_CONFIG_HOME/nodes"
printf '%s\n' \
  '[job]' \
  'id=local-demo' \
  'remote=localhost' \
  'stage_dir=/tmp/ilma-stage/local-demo' \
  '[manifest]' \
  '+ ./' \
  '- **' \
  > "$ILMA_CONFIG_HOME/nodes/local-demo.ini"
ilma remote list
bash commands/remote.sh list
```

Show remote pull options and the required job format.
```bash
ilma remote pull --help
bash commands/remote.sh pull --help
```

## Testing

Run the full suite with `tests/run.sh`. Each test is a bash script under `tests/`,
excluding `tests/helpers`.
```bash
tests/run.sh
```

## Linting

Linting is managed by pre-commit. If you have it installed, run:
```bash
pre-commit run --all-files
```
The hooks run `shfmt` and `shellcheck`; the versions and arguments live in
`.pre-commit-config.yaml`.
