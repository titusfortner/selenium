"""Assert every published artifact carries all four Selenium Manager binaries."""

import glob
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

SLOTS = ["linux-x86_64", "linux-arm64", "macos", "windows"]


def binary(slot):
    return "selenium-manager.exe" if slot == "windows" else "selenium-manager"


def outputs(label):
    out = subprocess.run(
        ["bazel", "cquery", "--output=files", label],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    return [Path(p) for p in out]


def names_in(path):
    if path.suffix in (".jar", ".whl", ".nupkg"):
        with zipfile.ZipFile(path) as z:
            return z.namelist()
    if path.suffix == ".gem":
        with tarfile.open(path) as outer:
            data = outer.extractfile("data.tar.gz")
            with tarfile.open(fileobj=data, mode="r:gz") as inner:
                return inner.getnames()
    raise SystemExit(f"unhandled artifact type: {path}")


def check(label, prefix, expected=None):
    expected = expected or [f"{prefix}{s}/{binary(s)}" for s in SLOTS]
    found = names_in(outputs(label)[0])
    missing = [e for e in expected if not any(n.endswith(e) for n in found)]
    print(f"{'FAIL' if missing else 'ok  '}  {label}")
    for m in missing:
        print(f"        missing {m}")
    return not missing


def check_tree(label, prefix):
    root = outputs(label)[0]
    missing = [s for s in SLOTS if not (root / prefix / s / binary(s)).is_file()]
    print(f"{'FAIL' if missing else 'ok  '}  {label}")
    for m in missing:
        print(f"        missing {prefix}/{m}/{binary(m)}")
    return not missing


results = [
    check("//java/src/org/openqa/selenium/manager:manager", "org/openqa/selenium/manager/"),
    check("//py:selenium-wheel", "selenium/webdriver/common/"),
    check("//rb:selenium-webdriver", "bin/"),
    check_tree("//javascript/selenium-webdriver:selenium-webdriver", "bin"),
    check(
        "//dotnet/src/webdriver:webdriver-pack",
        None,
        expected=[
            "runtimes/linux-x64/native/selenium-manager",
            "runtimes/linux-arm64/native/selenium-manager",
            "runtimes/osx/native/selenium-manager",
            "runtimes/win/native/selenium-manager.exe",
        ],
    ),
]
sys.exit(0 if all(results) else 1)
