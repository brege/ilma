## Roadmap

- Is orchestration of multiple remotes (like a tech lab) an external
  should-be-Bash task or within the scope of ilma? 

- Current `.ilma.conf` uses rsync‑specific args that leak transport
  tool specifics, and mixed with fragmented bash contructs.
  
  Consider implementing a proper schema for project types.

- Moving pruned files to a structured Trash directory instead of
  permanently deleting them.

- Better chunking/ciphered chunk streamer so interrupted jobs can be
  completed without a full re-run. 
