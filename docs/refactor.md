# Refactor Proposal: ilma Command Architecture

## Problem
The ilma codebase has grown into a monolithic dispatcher pattern where:
- Main ilma script: ~950 lines handling argument parsing, help text, command dispatch
- Each command file: 50-300 lines, but depends on setup/parsing in main ilma
- Result: debugging any command requires reading ilma + the command file (1000+ line context)
- Help text is duplicated/inconsistent across help hardcoded in ilma and command files
- Adding new commands requires modifying the main ilma script

## Proposed Architecture

### Before
```
ilma (950 lines)
  - Argument parsing for ALL commands
  - Help text for ALL commands
  - Command-specific setup logic
  - Case statements for each command
  - Calls: commands/backup.sh, commands/extract.sh, etc.

commands/backup.sh (341 lines)
  - Depends on variables set by ilma
  - Own internal functions
```

### After
```
ilma (50-75 lines)
  - Detect command name
  - If --help, call: commands/$COMMAND.sh --help
  - Otherwise: call: commands/$COMMAND.sh "$@"
  - Pass through all original arguments unchanged
  - Done

commands/backup.sh (self-contained)
  - Parse all arguments
  - Generate help text
  - Execute command
  - No dependencies on ilma setup

commands/extract.sh (self-contained)
  - Parse all arguments
  - Generate help text
  - Execute command

commands/decrypt.sh (self-contained)
  - etc.

commands/prune.sh (self-contained)
  - etc.

commands/validate.sh (self-contained)
  - etc.

commands/config.sh (self-contained)
  - etc.

commands/scan.sh (self-contained)
  - etc.

commands/console.sh (self-contained)
  - etc.

lib/ (shared utilities - unchanged)
```

## Implementation Steps

1. **Create base command template** (`commands/_template.sh`)
   - Standard argument parsing pattern
   - Standard help text generation
   - Standard error handling
   - All commands inherit this pattern

2. **Refactor each command**
   - Extract from ilma: argument parsing + help text for that command
   - Move into `commands/$COMMAND.sh`
   - Make command file entirely self-contained
   - Order: backup → extract → decrypt → prune → validate → config → scan → console

3. **Simplify ilma**
   - Remove all command-specific parsing
   - Remove all help text generation
   - Remove all case statements
   - Keep only: command detection + delegation

4. **Update tests**
   - Each command can now be tested independently
   - ilma itself has minimal logic to test

## Benefits
- Single file to understand per command (1 file, not 2+)
- Adding commands requires no changes to ilma
- Help text lives with implementation
- Consistent pattern across all commands
- Debugging context drops from 1000+ lines to ~300-400 per command
- Command files become independently executable/testable
- Clear separation of concerns

## Scope
- No functional changes
- Pure refactoring
- All existing features preserved
- All existing command behavior unchanged

## Estimated Effort
- Per-command refactoring: 1-2 hours each
- 8 commands × 1.5 hours average = ~12 hours
- ilma simplification: 1-2 hours
- Testing/verification: 2-3 hours
- **Total: ~15-17 hours**

## Risk Assessment
- Low risk: no behavioral changes, only code reorganization
- Mitigation: maintain full test coverage throughout
- Verification: test each command independently before final integration
