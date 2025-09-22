## RC Checklist (Safety / Portability / Maintainability)

A quick, no-features checklist.

Safety
- [x] Extract preflight rejects absolute and `..` paths (tar -tf check)
- [x] “Safely extracting …” logs only after preflight passes
- [x] Remote hash compare uses cd + quoted paths; shasum/openssl fallbacks
- [ ] Destructive ops guarded (e.g., rm only on real dirs; consider `-L` guard)

Portability
- [ ] No unguarded GNU-only calls (`readlink -f`, `stat -f -c`, `cp --reflink`)
- [ ] Hash tools work on macOS (shasum/md5/openssl) and GNU (*sum)
- [ ] Paths/args consistently quoted; rsync trailing slashes intentional

Maintainability
- [x] ShellCheck clean for changed files
- [ ] Logs/timestamps consistent; prefer UTC where practical
- [ ] Central helpers used for compression/rsync/gpg/path logic

Config/Docs
- [x] `[verify] enabled` supported in config.ini (default false)
- [x] `VERIFY=true` supported in .ilma.conf
- [x] Help/README show `--verify` usage

Known Hygiene (not features)
- [ ] Add portable fs/path detection shim in `lib/functions.sh` (readlink/stat/cp)
- [ ] Optional: refactor inline ssh in `lib/deps/rsync.sh` to here-doc
