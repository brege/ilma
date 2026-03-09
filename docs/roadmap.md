## Roadmap

- Keep `ilma` narrow:
  - pull
  - filter
  - archive
  - encrypt
  - extract

- Is orchestration of multiple remotes (like a tech lab) an external should-be-Bash task or within the scope of ilma? 

- Current `.ilma.conf` uses rsync‑specific args that leak transport tool specifics, and mixed with fragmented bash constructs.
  - consider implementing a proper schema for project types instead
  - could these be written like rsync filter files instead?

- Better chunking/ciphered chunk streamer so interrupted jobs can be completed without a full re-run. 
