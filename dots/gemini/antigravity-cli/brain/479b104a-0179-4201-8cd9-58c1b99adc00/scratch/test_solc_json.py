import json
import subprocess
import tempfile
from pathlib import Path
from auditor.corpus import get_contract
from auditor.label import _solc_binary, ensure_solc

def test_contract(bytecode_hash: str):
    c = get_contract(bytecode_hash)
    if not c:
        print("Contract not found")
        return
    
    print(f"Contract: {c.name}")
    print(f"Format: {c.source_format}")
    print(f"Solc version: {c.solc_version}")
    
    # ensure solc is installed
    solc_bins = ensure_solc({c.solc_version})
    bin_ = solc_bins.get(c.solc_version)
    print(f"Solc binary: {bin_}")
    
    with tempfile.TemporaryDirectory() as td:
        temp_dir = Path(td)
        print(f"Temp dir: {temp_dir}")
        
        # 1. Write the sources
        sources = c.sources()
        for path, content in sources.items():
            target_path = temp_dir / path
            target_path.parent.mkdir(parents=True, exist_ok=True)
            target_path.write_text(content, encoding="utf-8")
            print(f"  Wrote: {path}")
            
        # 2. Write the standard-JSON contract.json if it exists
        sj = c.standard_json()
        if sj:
            # Let's clean up settings if needed, or keep them as is.
            # The user says: "evmVersion yes, compiler version yes, optimizer/outputSelection/libraries no for labeling."
            # Actually, let's see if we can write contract.json directly to temp_dir
            # Wait, if we use pure solc, we don't even need --solc-standard-json if we just point to the main file!
            # Let's find the main contract file. It's the one whose path matches the contract name, or contains the contract name.
            # But wait! A standard-JSON can compile all sources in one go if we point solc at them.
            # Let's see if we can point Slither at the primary source file path (relative to temp_dir)
            pass
        
        # Let's write the remappings.txt
        settings = sj.get("settings", {}) if sj else {}
        remappings = settings.get("remappings", [])
        if remappings:
            remappings_file = temp_dir / "remappings.txt"
            remappings_file.write_text("\n".join(remappings) + "\n", encoding="utf-8")
            print(f"  Wrote remappings.txt: {remappings}")
            
        # Let's try compiling the main file.
        # How do we know the main file? Let's check which files contain 'contract Name'
        # Or even simpler: let's scan all .sol files written, and find the one that defines `contract Name`
        main_file = None
        for path in sources.keys():
            if Path(path).name == f"{c.name}.sol":
                main_file = path
                break
        if not main_file:
            # fallback: look for `contract <Name>` in contents
            for path, content in sources.items():
                if f"contract {c.name}" in content or f"library {c.name}" in content or f"interface {c.name}" in content:
                    main_file = path
                    break
        if not main_file:
            # ultimate fallback: the first source file
            main_file = list(sources.keys())[0]
            
        print(f"Main file: {main_file}")
        
        # Let's try running Slither in three different ways to see what works!
        # Method A: Point to the main file, cwd=temp_dir, with --solc-args "--base-path ."
        cmd_a = ["slither", main_file, "--json", "-"]
        if bin_:
            cmd_a += ["--solc", str(bin_)]
        cmd_a += ["--solc-args", "--base-path ."]
        
        print("\n--- Trying Method A (direct main file, base-path .) ---")
        p = subprocess.run(cmd_a, cwd=temp_dir, capture_output=True, text=True)
        print(f"Exit code: {p.returncode}")
        print(f"Stdout (first 200 chars): {p.stdout[:200]}")
        print(f"Stderr (first 500 chars): {p.stderr[:500]}")
        
        # Method B: Let's also try writing a foundry.toml to see if Crytic-compile compiles it as a Foundry project!
        (temp_dir / "foundry.toml").write_text(
            "[profile.default]\n"
            "src = \".\"\n"
            "out = \"out\"\n"
            "libs = []\n"
        )
        cmd_b = ["slither", ".", "--json", "-"]
        if bin_:
            cmd_b += ["--solc", str(bin_)]
        print("\n--- Trying Method B (Foundry compile, src=.) ---")
        p = subprocess.run(cmd_b, cwd=temp_dir, capture_output=True, text=True)
        print(f"Exit code: {p.returncode}")
        print(f"Stdout (first 200 chars): {p.stdout[:200]}")
        print(f"Stderr (first 500 chars): {p.stderr[:500]}")

if __name__ == "__main__":
    test_contract("00de144cad1914f06b465ab5f63fc1608bc5112b53a067a0486426b882679c4e")
