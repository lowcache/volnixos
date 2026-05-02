#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV_PATH=$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)
if [ -d "$VENV_PATH" ]; then
    source "$VENV_PATH/bin/activate"
    GIO_USE_VFS=local "$SCRIPT_DIR/thumbgen.py" "$@"
    THUMBGEN_EXIT_CODE=$?
    deactivate
else
    echo "Warning: Virtual environment not found at $VENV_PATH. Falling back to system python."
    GIO_USE_VFS=local python3 "$SCRIPT_DIR/thumbgen.py" "$@"
    THUMBGEN_EXIT_CODE=$?
fi

exit $THUMBGEN_EXIT_CODE
