#!/usr/bin/env python3
"""
REAPER-Notator - Pattern Library Packager
Compresses all 1200 orchestral & ancient harp patterns into patterns.zip
for instant 1-click in-app download and distribution.
"""

import os
import zipfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATTERNS_DIR = os.path.join(REPO_ROOT, "patterns")
ZIP_OUTPUT = os.path.join(REPO_ROOT, "patterns.zip")

def package_patterns():
    print(f"Packaging patterns from {PATTERNS_DIR} into {ZIP_OUTPUT}...")
    file_count = 0
    with zipfile.ZipFile(ZIP_OUTPUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for root, dirs, files in os.walk(PATTERNS_DIR):
            for file in files:
                full_path = os.path.join(root, file)
                # Store relative to REPO_ROOT (so it starts with 'patterns/...')
                rel_path = os.path.relpath(full_path, REPO_ROOT).replace("\\", "/")
                zf.write(full_path, rel_path)
                file_count += 1
                
    zip_size_kb = os.path.getsize(ZIP_OUTPUT) / 1024
    print(f"Successfully packaged {file_count} pattern files into {ZIP_OUTPUT} ({zip_size_kb:.1f} KB)")

if __name__ == "__main__":
    package_patterns()
