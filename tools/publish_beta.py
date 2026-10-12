#!/usr/bin/env python3
"""
REAPER-Notator - ReaPack Pre-Release Publisher (Variante A)
Synchronizes index.xml from the testing branch to the main branch
so that ReaPack users with pre-releases enabled receive the update immediately
without requiring repository URL changes or merging unreleased code into main.

Usage:
    python tools/publish_beta.py
"""

import sys
import os
import subprocess
import re

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION_LUA = os.path.join(REPO_ROOT, "modules", "version.lua")

def run_git(args, cwd=REPO_ROOT):
    result = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Git command failed: git {' '.join(args)}\nError: {result.stderr.strip()}")
    return result.stdout.strip()

def get_current_version():
    with open(VERSION_LUA, "r", encoding="utf-8") as f:
        content = f.read()
    maj = re.search(r"major\s*=\s*(\d+)", content)
    min_ = re.search(r"minor\s*=\s*(\d+)", content)
    pat = re.search(r"patch\s*=\s*(\d+)", content)
    suf = re.search(r'suffix\s*=\s*"([^"]*)"', content)
    if not (maj and min_ and pat):
        raise ValueError("Could not parse version from modules/version.lua")
    return f"{maj.group(1)}.{min_.group(1)}.{pat.group(1)}{suf.group(1) if suf else ''}"

def main():
    print("=== REAPER-Notator ReaPack Pre-Release Publisher ===")
    
    # 1. Check clean status
    status = run_git(["status", "--porcelain"])
    if status:
        print("ERROR: Working directory has uncommitted changes. Please commit or stash first:")
        print(status)
        sys.exit(1)
    
    # 2. Get current branch
    current_branch = run_git(["branch", "--show-current"])
    print(f"Current branch: {current_branch}")
    
    # 3. Get version
    semver = get_current_version()
    print(f"Current version: v{semver}")
    
    if not ("-" in semver or "beta" in semver.lower() or "rc" in semver.lower()):
        print("WARNING: This version does not appear to be a pre-release / beta.")
        confirm = input("Are you sure you want to publish it to the pre-release channel? (y/N): ")
        if confirm.lower() != "y":
            print("Aborted.")
            sys.exit(0)
    
    try:
        # 4. Switch to main
        print("\nSwitching to main branch...")
        run_git(["checkout", "main"])
        
        # 5. Bring in index.xml from the source branch
        print(f"Copying index.xml from {current_branch}...")
        run_git(["checkout", current_branch, "--", "index.xml"])
        
        # 6. Commit on main
        print("Committing index.xml on main...")
        run_git(["add", "index.xml"])
        commit_msg = f"chore(reapack): publish v{semver} to pre-release channel"
        run_git(["commit", "-m", commit_msg])
        
        # 7. Push main
        print("Pushing main to origin...")
        run_git(["push", "origin", "main"])
        print("Successfully pushed index.xml to origin/main!")
        
    except Exception as e:
        print(f"\nERROR during publication: {e}")
    finally:
        # 8. Return to original branch
        print(f"Returning to original branch '{current_branch}'...")
        run_git(["checkout", current_branch])
        print("Done! ReaPack pre-release channel updated.")

if __name__ == "__main__":
    main()

