#!/usr/bin/env python3
import sys
import subprocess
from pathlib import Path
import json

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "message": "Missing file_path argument."}))
        sys.exit(1)
        
    file_path = sys.argv[1]
    p = Path(file_path)
    if not p.exists():
        print(json.dumps({"status": "error", "message": f"File '{file_path}' not found."}))
        sys.exit(1)
        
    try:
        subprocess.run(["nixpkgs-fmt", str(p)], capture_output=True, text=True, check=True)
        print(json.dumps({"status": "success", "message": f"Formatted and validated layout syntax for {p.name}."}))
    except subprocess.CalledProcessError as e:
        print(json.dumps({
            "status": "error", 
            "message": f"Syntax violation detected by nixpkgs-fmt:\n{e.stderr or e.stdout}"
        }))

if __name__ == "__main__":
    main()
