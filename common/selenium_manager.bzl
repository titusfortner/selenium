# This file has been generated using `bazel run scripts:selenium_manager`

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")

def selenium_manager():
    http_file(
        name = "download_sm_linux",
        executable = True,
        sha256 = "b417e4faad5ab781102f6ba83f0bfc39b60343fbc43455a2732cab82420dcd0e",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-53771af/selenium-manager-linux",
    )

    http_file(
        name = "download_sm_macos",
        executable = True,
        sha256 = "f0990a97a24db5b0aa9d2fcbc7b69eaad11e96a4f3a75887f667b874bdc5e713",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-53771af/selenium-manager-macos",
    )

    http_file(
        name = "download_sm_windows",
        executable = True,
        sha256 = "d35639fa4f9e57d5b8124cd0bff16dc3ee22323d07f4ae1c644964b627e1d190",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-53771af/selenium-manager-windows.exe",
    )
