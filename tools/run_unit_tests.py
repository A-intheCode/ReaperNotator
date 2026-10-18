#!/usr/bin/env python3
"""
REAPER-Notator - Automated Headless Lua Unit Test & Crash Fuzzer Runner
Executes tests/test_all_modules.lua inside Python's lupa (Lua 5.5) runtime.
"""

import os
import sys
import lupa

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")

def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.globals().TEST_REPO_ROOT = REPO_ROOT
    test_file = os.path.join(REPO_ROOT, "tests", "test_all_modules.lua").replace("\\", "/")
    with open(test_file, "r", encoding="utf-8") as f:
        code = f.read()
    res = lua.execute(code)
    failed = int(res["failed"]) if res and "failed" in res else 0
    sys.exit(1 if failed > 0 else 0)

if __name__ == "__main__":
    main()

