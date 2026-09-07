@echo off
SETLOCAL

REM Shim so `./go` works from PowerShell and cmd; the real wrapper is the bash `go` next to it.
REM Prefer BAZEL_SH because a bare `bash` can resolve to the WSL launcher in System32.
SET "GO_SH=bash"
IF DEFINED BAZEL_SH SET "GO_SH=%BAZEL_SH%"
"%GO_SH%" "%~dp0go" %*
exit /b %ERRORLEVEL%
