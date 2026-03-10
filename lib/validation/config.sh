#!/bin/bash
# lib/validation/config.sh - Basic configuration validation

PROJECT_ROOT="${1:-$(pwd)}"

echo "SECTION:Basic Configuration"

# Check if project directory exists and is accessible
if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "FAIL:Project directory accessibility:Directory '$PROJECT_ROOT' does not exist"
  exit 1
fi
echo "PASS:Project directory accessibility"

# Check for configuration files
config_found=false
if [[ -f "$PROJECT_ROOT/.ilma.conf" ]]; then
  config_found=true
  echo "PASS:Configuration file found"
fi

if [[ "$config_found" == false ]]; then
  echo "INFO:No per-project config (.ilma.conf) detected - using default"
fi
