#!/usr/bin/env python3
"""
REAPER-Notator - Automated Version Bumper & ReaPack Release Manager
Usage:
    python tools/bump_version.py            # Show current version
    python tools/bump_version.py patch      # 1.0.0 -> 1.0.1 (stable release)
    python tools/bump_version.py minor      # 1.0.0 -> 1.1.0 (stable release)
    python tools/bump_version.py major      # 1.0.0 -> 2.0.0 (stable release)
    python tools/bump_version.py beta       # 1.0.0 -> 1.0.1-beta (pre-release channel)
    python tools/bump_version.py 1.9.9-beta # Explicit pre-release version
    python tools/bump_version.py 1.9.9      # Explicit stable release version
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
    elif action == "beta":
        if suffix.startswith("-beta"):
            m_b = re.match(r"^-beta\.?(\d+)?$", suffix)
            if m_b and m_b.group(1):
                num = int(m_b.group(1)) + 1
                return major, minor, patch, f"-beta.{num}"
            else:
                return major, minor, patch, "-beta.1"
        else:
            return major, minor, patch + 1, "-beta"
    else:
        # Explicit version string like 1.2.3 or 1.2.3-beta
        m = re.match(r"^(\d+)\.(\d+)\.(\d+)(.*)$", action)
        if m:
            return int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
        else:
            raise ValueError(f"Invalid version argument: '{action}'. Use patch, minor, major, beta, or X.Y.Z")

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
    is_beta = ("-" in semver and "deprecated" not in semver.lower()) or ("beta" in semver.lower()) or ("rc" in semver.lower())

    # Match all <version ...> ... </version> blocks
    matches = list(re.finditer(r'([ \t]*<version name="([^"]+)" author="([^"]+)" time="[^"]+">.*?</version>)', content, re.DOTALL))
    if not matches:
        print("Warning: Could not find <version> block in index.xml")
        return

    beta_match = None
    stable_match = None
    for m in matches:
        v_name = m.group(2)
        v_is_beta = ("-" in v_name and "deprecated" not in v_name.lower()) or ("beta" in v_name.lower()) or ("rc" in v_name.lower())
        if v_is_beta and beta_match is None:
            beta_match = m
        elif not v_is_beta and "deprecated" not in v_name.lower() and stable_match is None:
            stable_match = m

    if is_beta:
        if beta_match:
            # Update the existing Beta block in-place without touching any Release block
            target_m = beta_match
            new_block = target_m.group(1)
            new_block = re.sub(r'<version name="[^"]+" author="([^"]+)" time="[^"]+">',
                               f'<version name="{semver}" author="\\1" time="{now}">',
                               new_block, count=1)
            new_block = re.sub(r'/ReaperNotator/main/', r'/ReaperNotator/testing/', new_block)
            if changelog_note:
                note_str = f"+ v{semver}: {changelog_note}\n"
                new_block = re.sub(r'(<changelog><!\[CDATA\[\n)', f'\\1{note_str}', new_block, count=1)
            content = content[:target_m.start(1)] + new_block + content[target_m.end(1):]
        else:
            # Prepend a new Beta block on top without deleting the Release block
            first_m = matches[0]
            new_block = first_m.group(1)
            new_block = re.sub(r'<version name="[^"]+" author="([^"]+)" time="[^"]+">',
                               f'<version name="{semver}" author="\\1" time="{now}">',
                               new_block, count=1)
            new_block = re.sub(r'/ReaperNotator/main/', r'/ReaperNotator/testing/', new_block)
            note_str = f"+ v{semver}: {changelog_note}\n" if changelog_note else f"+ v{semver}: Beta pre-release\n"
            new_block = re.sub(r'<changelog><!\[CDATA\[.*?\]\]></changelog>',
                               f'<changelog><![CDATA[\n{note_str}        ]]></changelog>',
                               new_block, flags=re.DOTALL)
            content = content[:first_m.start(1)] + new_block + "\n" + content[first_m.start(1):]
    else:
        # Stable Release: NEVER delete the Beta block! Update or insert the Stable Release block separately.
        if stable_match:
            target_m = stable_match
            new_block = target_m.group(1)
            new_block = re.sub(r'<version name="[^"]+" author="([^"]+)" time="[^"]+">',
                               f'<version name="{semver}" author="\\1" time="{now}">',
                               new_block, count=1)
            new_block = re.sub(r'/ReaperNotator/testing/', r'/ReaperNotator/main/', new_block)
            if changelog_note:
                note_str = f"+ v{semver}: {changelog_note}\n"
                new_block = re.sub(r'(<changelog><!\[CDATA\[\n)', f'\\1{note_str}', new_block, count=1)
            content = content[:target_m.start(1)] + new_block + content[target_m.end(1):]
        else:
            first_m = matches[0]
            new_block = first_m.group(1)
            new_block = re.sub(r'<version name="[^"]+" author="([^"]+)" time="[^"]+">',
                               f'<version name="{semver}" author="\\1" time="{now}">',
                               new_block, count=1)
            new_block = re.sub(r'/ReaperNotator/testing/', r'/ReaperNotator/main/', new_block)
            if changelog_note:
                note_str = f"+ v{semver}: {changelog_note}\n"
                new_block = re.sub(r'(<changelog><!\[CDATA\[\n)', f'\\1{note_str}', new_block, count=1)
            content = content[:first_m.start(1)] + new_block + "\n" + content[first_m.start(1):]

    with open(INDEX_XML, "w", encoding="utf-8") as f:
        f.write(content)

def main():
    major, minor, patch, suffix = get_current_version()
    current_semver = f"{major}.{minor}.{patch}{suffix}"
    
    if len(sys.argv) < 2:
        print(f"Current REAPER-Notator version: v{current_semver}")
        print("To bump version, run:")
        print("  python tools/bump_version.py patch          # e.g. bug fixes, minor tweaks (stable)")
        print("  python tools/bump_version.py minor          # e.g. new features, UI additions (stable)")
        print("  python tools/bump_version.py major          # e.g. breaking architectural release (stable)")
        print("  python tools/bump_version.py beta           # bumps patch and sets -beta suffix (pre-release)")
        print("  python tools/bump_version.py 1.9.9-beta     # explicit semantic pre-release version")
        print("  python tools/bump_version.py 1.9.9          # explicit semantic stable version")
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
    
    is_beta = ("-" in new_semver and "deprecated" not in new_semver.lower()) or ("beta" in new_semver.lower())
    if is_beta:
        print("\nPre-Release (Beta) next steps:")
        print(f'  1. Commit on testing:  git add . && git commit -m "chore(release): v{new_semver}" && git push origin testing')
        print(f'  2. Publish to ReaPack: python tools/publish_beta.py')
    else:
        print("\nStable Release next steps:")
        print(f'  1. Commit on main:     git add . && git commit -m "chore(release): v{new_semver}" && git push origin main')
        print(f'  2. Sync to testing:    git checkout testing && git merge main && git push origin testing')

if __name__ == "__main__":
    main()
