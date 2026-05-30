#!/usr/bin/env python3
import subprocess
import json

def main():
    try:
        res = subprocess.run(["nix-doctor"], capture_output=True, text=True, check=True)
        print(json.dumps({"status": "healthy", "output": res.stdout}))
    except FileNotFoundError:
        print(json.dumps({"status": "error", "message": "nix-doctor utility not found in current PATH profile."}))
    except subprocess.CalledProcessError as e:
        print(json.dumps({"status": "degraded", "output": e.stderr or e.stdout}))

if __name__ == "__main__":
    main()
