## Future: Roadmap and Design Directions

- 100% shell
- Ergonomic args (tar, rsync, gpg under one roof)
- Separation of policy from execution  

---

1. [**point-release**] **Manifests and Central Orchestration**  
   Want to perform backups from a central machine that oversees multiple \*nix boxes without coupling to rsync/GPG particulars per user.

   **Manifest Syntax**  
   - [ ] INI-like or `KEY=VALUE` file parsed by a constrained reader (no `eval`), arrays as newline-separated values.  
     
   Example schema
   ```ini
   [job]
   name=projX
   origins=/srv/projX
   type=python
   mode=backup,archive,encrypt
   basename=projX
   target_dir=/backups/projX

   [policy]
   compression=zstd
   compression_level=3
   versioning=timestamp
   max_archives=7

   [remote]
   server=backup@host
   path=/srv/archives
   verify=sha256
   cleanup_after=true
   ```
   
   Flow  
     1. Central host compiles per-host job scripts (pure shell templates).  
     2. Push via ssh/rsync or pull, execute with a minimal runner.  
     3. Collect results into signed job reports with hashes, sizes, timestamps.  
   
   This syntactic redesign separates user config from rsync quirks, providing reproducibility and provenance trail.  

2. [**refactor**] **Gentler Configuration Surface**  
   Current `.ilma.conf` uses rsync‑specific args that leak transport tool specifics.  
   
   - [ ] Domain‑specific keys the tool translates internally.  
     - `EXCLUDE_DIRS=(node_modules dist build __pycache__ venv)`  
     - `EXCLUDE_GLOBS=('*.log' '*.tmp')`

   This is something that would be wiser to do now, than painfully make compatible later.

3. [**later**] **Trash + Restore (Safe Prune)**  
   - [ ] Deletion moves files into `.ilma-trash/<epoch>-<sha256[:8]>` with metadata.  
   - [ ] Metadata index records original path, size, and mtime.  
   - [ ] `ilma restore <hash|path>` recovers them safely.  

4. [**easy**] **Statistics and Console Enhancements**  
   - [ ] Extend console summaries by file extension and size classes using `lib/stats.sh`.  
   - [ ] Optional JSON output for machine ingestion (CI/cron).  

5. [**easy**] **Flag Commutativity and Multi-type Merging**  
   - [ ] Centralize post-operation logic so `-r|--remote` commutes with `-a/-e/-b`.  
   - [ ] Consider merging multiple `--type` presets.

6. [**easy**] **Platform Support and Fallbacks**  
   Provide shims for portability across Linux/BSD/macOS:  
     - [ ] `realpath`/`readlink`  
     - [ ] `stat` flags  
     - [ ] `cp` reflink detection  
     - [ ] hash tool differences (`sha256sum` vs `shasum`)  

---

#### Strategy
 
 1. Hardening `docs/rc.md`
 2. Config Surface  
 3. Manifests
 4. Orchestration  

---

#### Minimal Provenance for Artifacts

Generate sidecar `.manifest` files containing:  
 - job name, project root  
 - operations performed  
 - compression type + level  
 - hashes, sizes, UTC timestamp, tool version  
 - optional GPG recipient fingerprint  
 - stored alongside artifacts or in `.bak/.context`.  
This might not be something that needs to be entirely implemented now, just that we should design toward it as destination.

#### Runner Layout for Bots

 - On each host: minimal `sh` runner executes one job bundle, outputs result JSON.  
 - On central: compiler builds job bundles from manifests, distributes, collects results.  
 - Communication via SSH restricted keys; signing/verifying bundles optional later.  
 - Supporting `.ilma.conf` memories.

#### Chunked Uploads (Low-space, Resumable)
 
 Stream files into ciphered chunks:  
 ```bash
 tar -cf - path | <compress> | gpg --encrypt ... \
   | split -b "$CHUNK_SIZE" -d -a 4 - "base.part"
 ```
   - *Sidecar manifest:* overall SHA256, chunk size, part list, optional per‑part hashes.  
   - *Upload loop:* rsync parts atomically, clean up locally if `LOW_SPACE=true`, verify remote with concatenated hash, upload `.remote-ok`.  
   - *Resume:* detect existing `.part*` files remotely, continue at first missing index.  
 
 **Testing Candidate**  
   - Tie into existing `--verify` (no CLI change, just extended implementation).  
   - Example: Fedora 12 netinst ISO (202MB) end-to-end test.  
     ```bash
     export CHUNK_SIZE=32M
     export VERIFY=true

     ilma -e --verify --remote server:/home/user/landing \
       /path/to/Fedora-12-i386-netinst.iso

     ssh server 'cd /home/user/landing && \
       cat Fedora-12-i386-netinst.iso.part* | sha256sum -'
     ```

