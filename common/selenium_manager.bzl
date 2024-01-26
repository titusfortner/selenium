# This file has been generated using `bazel run scripts:selenium_manager`

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")

def selenium_manager():
    http_file(
        name = "download_sm_linux",
        executable = True,
        sha256 = "8f11d3e6aa028e7625d0323e9348afc82bde818d8a4ba0e273ae301aa5112230",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-d089802/selenium-manager-linux",
    )

    http_file(
        name = "download_sm_macos",
        executable = True,
        sha256 = "bd7530c0132b60a2922f85e38e0780603423c1f9ff1e8dcb3d7725664de02556",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-d089802/selenium-manager-macos",
    )

    http_file(
        name = "download_sm_windows",
        executable = True,
        sha256 = "ee6042eb0c4ffe139d0c8ef394c0069c3667bd84eed0435aedf97e2e45e7903a",
        url = "https://github.com/SeleniumHQ/selenium_manager_artifacts/releases/download/selenium-manager-d089802/selenium-manager-windows.exe",
    )
