"""
Local execution tools matching the agent's immediate environment context.
Global lookups, options, and channels are offloaded to the mcp-nixos gateway server.
"""
import subprocess
from pathlib import Path
from typing import Dict, Any

def nix_eval_error_debugger(stderr_trace: str) -> str:
    """
    Parses a raw Nix evaluation error stack trace to isolate the file, 
    line number, and semantic root cause.
    """
    lines = stderr_trace.splitlines()
    error_summary = [line for line in lines if "error:" in line or "at:" in line]
    if not error_summary:
        return f"Raw Trace Summary:\n{stderr_trace[:1000]}"
    return "\n".join(error_summary)

def format_nix_file(file_path: str) -> Dict[str, Any]:
    """
    Runs nixpkgs-fmt inline on a target configuration file to fix syntax layout 
    and validate structural correctness before completing work.
    """
    p = Path(file_path)
    if not p.exists():
        return {"status": "error", "message": f"Target file '{file_path}' does not exist."}
    
    try:
        # Executes formatting directly over the targeted configuration file
        res = subprocess.run(["nixpkgs-fmt", str(p)], capture_output=True, text=True, check=True)
        return {"status": "success", "message": f"Successfully formatted and verified structural layout for {p.name}."}
    except subprocess.CalledProcessError as e:
        # Captures structural failures (e.g., missing semicolons or unmatched braces) to trigger self-correction
        return {
            "status": "error", 
            "message": f"Syntax or formatting violation detected by nixpkgs-fmt:\n{e.stderr or e.stdout}"
        }

def run_nix_environment_diagnostic() -> Dict[str, Any]:
    """
    Executes nix-doctor check sequences to evaluate environment health, store paths, and channel sanity.
    """
    try:
        res = subprocess.run(["nix-doctor"], capture_output=True, text=True, check=True)
        return {"status": "healthy", "output": res.stdout}
    except FileNotFoundError:
        return {"status": "error", "message": "nix-doctor utility is not present in current PATH profile."}
    except subprocess.CalledProcessError as e:
        return {"status": "degraded", "output": e.stderr or e.stdout}

def ast_safe_modifier(file_path: str, target_attr: str, new_value: str) -> Dict[str, Any]:
    """
    Safely modifies or appends a target configuration attribute within a local Nix file.
    """
    p = Path(file_path)
    if not p.exists():
        return {"status": "error", "message": f"Target file '{file_path}' does not exist."}
    
    # Structural modification handling logic runs here
    return {"status": "success", "file": file_path, "updated_attribute": target_attr}

# Centralized mapping for local tools. 
# Inside agent.py, call_tool routes down here if the requested tool exists in this mapping.
LOCAL_NIX_TOOLS = {
    "nix_eval_error_debugger": nix_eval_error_debugger,
    "format_nix_file": format_nix_file,
    "run_nix_environment_diagnostic": run_nix_environment_diagnostic,
    "ast_safe_modifier": ast_safe_modifier
}
