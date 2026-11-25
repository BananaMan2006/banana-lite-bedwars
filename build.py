from pathlib import Path

root = Path(__file__).resolve().parent
core = (root / "core.lua").read_text()
tests = (root / "selftest.lua").read_text()
runtime = (root / "runtime.lua").read_text()
bundle = "-- BananaLite 0.1.0 | original source | normal gameplay limits\n"
bundle += "local Core = (function()\n" + core + "\nend)()\n"
bundle += "local SelfTest = (function()\n" + tests + "\nend)()\n"
bundle += runtime
(root / "banana-lite.lua").write_text(bundle)
print(f"Built {root / 'banana-lite.lua'} ({len(bundle.encode())} bytes)")
