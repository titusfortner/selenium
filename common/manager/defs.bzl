"""Shared definitions for the cross-compiled Selenium Manager binaries."""

SELENIUM_MANAGER_PLATFORMS = [
    "linux-arm64",
    "linux-x86_64",
    "macos-arm64",
    "macos-x86_64",
    "windows-arm64",
    "windows-x86_64",
]

def selenium_manager_binary(platform):
    """Label of the Selenium Manager binary built for `platform`."""
    return "//common/manager:selenium-manager-%s" % platform

def selenium_manager_filename(platform):
    """File name the binary is shipped under for `platform`."""
    return "selenium-manager.exe" if platform.startswith("windows") else "selenium-manager"
