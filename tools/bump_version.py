#!/usr/bin/env python3
"""
REAPER-Notator - Automated Version Bumper
Usage:
    python tools/bump_version.py            # Show current version
    python tools/bump_version.py patch      # 1.0.0 -> 1.0.1
    python tools/bump_version.py minor      # 1.0.0 -> 1.1.0
    python tools/bump_version.py major      # 1.0.0 -> 2.0.0
    python tools/bump_version.py 1.2.0      # Explicit version
"""

import sys
import os
import re
import datetime

# Root directory of REAPER-Notator
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION_LUA = os.path.join(REPO_ROOT, "modules", "version.lua")
MAIN_LUA = os.path.join(REPO_ROOT, "reaper_native_notator.lua")
INDEX_XML = os.path.join(REPO_ROOT, "index.xml")

def get_current_version():
    with open(VERSION_LUA, "r", encoding="utf-8") as f:
        content = f.read()
    
    maj = re.search(r"major\s*=\s*(\d+)", content)
    min_ = re.search(r"minor\s*=\s*(\d+)", content)
    pat = re.search(r"patch\s*=\s*(\d+)", content)
    suf = re.search(r'suffix\s*=\s*"([^"]*)"', content)
    
    if not (maj and min_ and pat):
        raise ValueError("Could not parse version from modules/version.lua")
    
    major = int(maj.group(1))
    minor = int(min_.group(1))
    patch = int(pat.group(1))
    suffix = suf.group(1) if suf else ""
    return major, minor, patch, suffix

def compute_new_version(action, major, minor, patch, suffix):
    if action == "patch":
        return major, minor, patch + 1, ""
    elif action == "minor":
        return major, minor + 1, 0, ""
    elif action == "major":
        return major + 1, 0, 0, ""
    else:
        # Explicit version string like 1.2.3 or 1.2.3-rc1
        m = re.match(r"^(\d+)\.(\d+)\.(\d+)(.*)$", action)
        if m:
            return int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
        else:
            raise ValueError(f"Invalid version argument: '{action}'. Use patch, minor, major, or X.Y.Z")

def update_version_lua(major, minor, patch, suffix):
    with open(VERSION_LUA, "r", encoding="utf-8") as f:
        content = f.read()
    
    content = re.sub(r"major\s*=\s*\d+", f"major = {major}", content)
    content = re.sub(r"minor\s*=\s*\d+", f"minor = {minor}", content)
    content = re.sub(r"patch\s*=\s*\d+", f"patch = {patch}", content)
    content = re.sub(r'suffix\s*=\s*"[^"]*"', f'suffix = "{suffix}"', content)
    
    with open(VERSION_LUA, "w", encoding="utf-8") as f:
        f.write(content)

def update_main_lua(semver):
    with open(MAIN_LUA, "r", encoding="utf-8") as f:
        content = f.read()
    
    # Replace ReaPack header @version
    content = re.sub(r"-- @version\s+[\d\.]+[^\s]*", f"-- @version {semver}", content)
    
    with open(MAIN_LUA, "w", encoding="utf-8") as f:
        f.write(content)

def update_index_xml(semver, changelog_note=None):
    if not os.path.exists(INDEX_XML):
        return
    with open(INDEX_XML, "r", encoding="utf-8") as f:
        content = f.read()
    
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    
    # Update version name and time in <version name="..." ... time="...">
    content = re.sub(r'<version name="[^"]+" author="([^"]+)" time="[^"]+">',
                     f'<version name="{semver}" author="\\1" time="{now}">',
                     content)
    
    if changelog_note:
        # Prepend to changelog
        note_str = f"+ v{semver}: {changelog_note}\n"
        content = re.sub(r'(<changelog><!\[CDATA\[\n)', f'\\1{note_str}', content)
    
    with open(INDEX_XML, "w", encoding="utf-8") as f:
        f.write(content)

def main():
    major, minor, patch, suffix = get_current_version()
    current_semver = f"{major}.{minor}.{patch}{suffix}"
    
    if len(sys.argv) < 2:
        print(f"Current REAPER-Notator version: v{current_semver}")
        print("To bump version, run:")
        print("  python tools/bump_version.py patch   # e.g. bug fixes, minor tweaks")
        print("  python tools/bump_version.py minor   # e.g. new features, UI additions")
        print("  python tools/bump_version.py major   # e.g. breaking architectural release")
        print("  python tools/bump_version.py 1.1.0   # explicit semantic version")
        return
    
    action = sys.argv[1].lower()
    note = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else f"Release v{action}"
    
    new_major, new_minor, new_patch, new_suffix = compute_new_version(action, major, minor, patch, suffix)
    new_semver = f"{new_major}.{new_minor}.{new_patch}{new_suffix}"
    
    print(f"Bumping version: v{current_semver} -> v{new_semver}")
    
    update_version_lua(new_major, new_minor, new_patch, new_suffix)
    update_main_lua(new_semver)
    update_index_xml(new_semver, note)
    
    print("Files updated:")
    print(f"  - {os.path.relpath(VERSION_LUA, REPO_ROOT)}")
    print(f"  - {os.path.relpath(MAIN_LUA, REPO_ROOT)}")
    print(f"  - {os.path.relpath(INDEX_XML, REPO_ROOT)}")
    print("\nNext steps:")
    print(f'  git add . && git commit -m "Bump version to v{new_semver}" && git push')

if __name__ == "__main__":
    main()
