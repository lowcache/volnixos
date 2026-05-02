#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV_PATH=$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)
if [ -d "$VENV_PATH" ]; then
    source "$VENV_PATH/bin/activate"
    "$SCRIPT_DIR/find_regions.py" "$@"
    deactivate
else
    echo "Warning: Virtual environment not found at $VENV_PATH. Falling back to system python."
    python3 "$SCRIPT_DIR/find_regions.py" "$@"
fi
