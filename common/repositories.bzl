# This file has been generated using `bazel run scripts:pinned_browsers`

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//common/private:dmg_archive.bzl", "dmg_archive")
load("//common/private:drivers.bzl", "local_drivers")
load("//common/private:pkg_archive.bzl", "pkg_archive")

def pin_browsers():
    local_drivers()

    http_archive(
        name = "linux_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/122.0/linux-x86_64/en-US/firefox-122.0.tar.bz2",
        sha256 = "0b36d796ba88d48000b0a3e43854a00556148221776879c91fae03735a0e5c21",
        build_file_content = """
filegroup(
    name = "files",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["firefox/firefox"],
)
""",
    )

    dmg_archive(
        name = "mac_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/122.0/mac/en-US/Firefox%20122.0.dmg",
        sha256 = "ccd68fe5388b044062410ce71885911f618fd4222cd617e429eb8ab0b68795d4",
        build_file_content = "exports_files([\"Firefox.app\"])",
    )

    http_archive(
        name = "linux_beta_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/123.0b3/linux-x86_64/en-US/firefox-123.0b3.tar.bz2",
        sha256 = "496be0e58074ce544a00fce8e67c36db685590f5ecc0319c8388fdda0b9f0dd0",
        build_file_content = """
filegroup(
    name = "files",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["firefox/firefox"],
)
""",
    )

    dmg_archive(
        name = "mac_beta_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/123.0b3/mac/en-US/Firefox%20123.0b3.dmg",
        sha256 = "ba06728492cbe18f1194cf7cd5e9ee3ad271cda5ae9e2f845851691911b72a84",
        build_file_content = "exports_files([\"Firefox.app\"])",
    )

    http_archive(
        name = "linux_dev_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/123.0b3/linux-x86_64/en-US/firefox-123.0b3.tar.bz2",
        sha256 = "496be0e58074ce544a00fce8e67c36db685590f5ecc0319c8388fdda0b9f0dd0",
        build_file_content = """
filegroup(
    name = "files",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["firefox/firefox"],
)
""",
    )

    dmg_archive(
        name = "mac_dev_firefox",
        url = "https://ftp.mozilla.org/pub/firefox/releases/123.0b3/mac/en-US/Firefox%20123.0b3.dmg",
        sha256 = "ba06728492cbe18f1194cf7cd5e9ee3ad271cda5ae9e2f845851691911b72a84",
        build_file_content = "exports_files([\"Firefox.app\"])",
    )

    http_archive(
        name = "linux_geckodriver",
        url = "https://github.com/mozilla/geckodriver/releases/download/v0.34.0/geckodriver-v0.34.0-linux64.tar.gz",
        sha256 = "79b2e77edd02c0ec890395140d7cdc04a7ff0ec64503e62a0b74f88674ef1313",
        build_file_content = "exports_files([\"geckodriver\"])",
    )

    http_archive(
        name = "mac_geckodriver",
        url = "https://github.com/mozilla/geckodriver/releases/download/v0.34.0/geckodriver-v0.34.0-macos.tar.gz",
        sha256 = "9cec1546585b532959782c8220599aa97c1f99265bb2d75ad00cd56ef98f650c",
        build_file_content = "exports_files([\"geckodriver\"])",
    )

    pkg_archive(
        name = "mac_edge",
        url = "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7a610a85-f171-4858-ab93-06908d04c1d6/MicrosoftEdge-121.0.2277.83.pkg",
        sha256 = "3b2b3b919558147dccf993a0d86f7eb04782b8d7f39aeb9c719b2dc381f262ba",
        move = {
            "MicrosoftEdge-121.0.2277.83.pkg/Payload/Microsoft Edge.app": "Edge.app",
        },
        build_file_content = "exports_files([\"Edge.app\"])",
    )

    http_archive(
        name = "linux_edgedriver",
        url = "https://msedgedriver.azureedge.net/120.0.2210.144/edgedriver_linux64.zip",
        sha256 = "2c44a4024444ccf702f52bc47cb7da8f4cca2653effde7db2462601bcfed7190",
        build_file_content = "exports_files([\"msedgedriver\"])",
    )

    http_archive(
        name = "mac_edgedriver",
        url = "https://msedgedriver.azureedge.net/120.0.2210.144/edgedriver_mac64.zip",
        sha256 = "16513695a0405fefab843a25202d84116ac6e7078b808df45b379160167f4b67",
        build_file_content = "exports_files([\"msedgedriver\"])",
    )

    http_archive(
        name = "linux_chrome",
        url = "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/122.0.6261.6/linux64/chrome-linux64.zip",
        sha256 = "ae9976196d8ec3f42c54a7bb6dea4051e6578268c04f5353ff1623c6903399f8",
        build_file_content = """
filegroup(
    name = "files",
    srcs = glob(["**/*"]),
    visibility = ["//visibility:public"],
)

exports_files(
    ["chrome-linux64/chrome"],
)
""",
    )

    http_archive(
        name = "mac_chrome",
        url = "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/122.0.6261.6/mac-x64/chrome-mac-x64.zip",
        sha256 = "53a61f985aa185ea313f83a3b172da84ec62693287c3b1dcb92ff0c4c9ccfb56",
        strip_prefix = "chrome-mac-x64",
        patch_cmds = [
            "mv 'Google Chrome for Testing.app' Chrome.app",
            "mv 'Chrome.app/Contents/MacOS/Google Chrome for Testing' Chrome.app/Contents/MacOS/Chrome",
        ],
        build_file_content = "exports_files([\"Chrome.app\"])",
    )

    http_archive(
        name = "linux_chromedriver",
        url = "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/122.0.6261.6/linux64/chromedriver-linux64.zip",
        sha256 = "502776181ae0ecf450b4a6943050cbe8eef40430a25a489fd2e46af5bca0f650",
        strip_prefix = "chromedriver-linux64",
        build_file_content = "exports_files([\"chromedriver\"])",
    )

    http_archive(
        name = "mac_chromedriver",
        url = "https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/122.0.6261.6/mac-x64/chromedriver-mac-x64.zip",
        sha256 = "a3aed446fab7b123d0a1cd93579156e144a61dad513fc4b451d291f059e62db3",
        strip_prefix = "chromedriver-mac-x64",
        build_file_content = "exports_files([\"chromedriver\"])",
    )
