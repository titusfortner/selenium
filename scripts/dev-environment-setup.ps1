# 1. Open PowerShell as an Administrator
# 2. Change directory to where you want Selenium repo to be cloned to
# 3. Execute: `Set-ExecutionPolicy Bypass -Scope Process -Force`
# 4. Run this script in the PowerShell terminal

$ErrorActionPreference = 'Stop'

Function Write-ErrorAndExit {
  param ([string]$Message)
  Write-Host "ERROR: $Message" -ForegroundColor Red
  exit 1
}

Function Install-ChocoPackage {
  param (
    [string]$PackageName,
    [string]$ExecutableName,
    [string]$AdditionalParams = ""
  )

  Write-Host "Checking installation of $PackageName"
  if (-Not (Get-Command $ExecutableName -ErrorAction SilentlyContinue)) {
    Write-Host "Installing $PackageName..."
    try {
      choco install $PackageName -y $AdditionalParams
      if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey returned exit code $LASTEXITCODE"
      }
      refreshenv
    } catch {
      Write-ErrorAndExit "Failed to install $PackageName : $_"
    }
  } else {
    Write-Host "$PackageName is already installed."
  }
}

Function Install-JDK17 {
  $javacInstalled = Get-Command javac -ErrorAction SilentlyContinue
  $javaVersion = if ($javacInstalled) { & javac -version 2>&1 | Select-String -Pattern 'javac (\d+)' | ForEach-Object { $_.Matches.Groups[1].Value } }

  if (-Not $javacInstalled -or -Not $javaVersion -or [int]$javaVersion -lt 17) {
    Install-ChocoPackage -PackageName "openjdk17" -ExecutableName "javac"
  } else {
    Write-Host "JDK 17 is already installed."
  }
}

Function Set-JavaEnvironmentVariable {
  Write-Host "Searching for javac.exe..."
  $javacPath = Get-ChildItem -Path 'C:\Program Files\' -Recurse -Filter 'javac.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName
  if (-Not $javacPath) {
    Write-ErrorAndExit "Could not find javac.exe in 'C:\Program Files\'. JDK installation may have failed."
  }
  $javaHome = Split-Path -Path $javacPath
  Write-Host "Set JAVA_HOME environment variable to $javaHome"
  [System.Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, [System.EnvironmentVariableTarget]::Machine)
  refreshenv
}

Function Update-EnvironmentVariable {
  Param ([string]$VariableName, [string]$Value)
  $currentValue = [Environment]::GetEnvironmentVariable($VariableName, [EnvironmentVariableTarget]::User)
  if (-not $currentValue -or $currentValue -ne $Value) {
    Write-Host "Setting $VariableName to $Value"
    [Environment]::SetEnvironmentVariable($VariableName, $Value, [System.EnvironmentVariableTarget]::User)
    refreshenv
  } else {
    Write-Host "$VariableName is already set to $currentValue"
  }
}

Function Add-ToPath {
  Param ([string]$PathToAdd)
  $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
  if ($currentPath -and $currentPath.Split(';') -contains $PathToAdd) {
    Write-Host "$PathToAdd is already in PATH"
  } else {
    Write-Host "Adding $PathToAdd to PATH"
    $newPath = if ($currentPath) { "$currentPath;$PathToAdd" } else { $PathToAdd }
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [System.EnvironmentVariableTarget]::User)
    refreshenv
  }
}

Function Clone-Repository {
  param (
    [string]$RepoUrl
  )
  $cloneChoice = Read-Host "Do you want to clone the repository at $RepoUrl (Y/N)"
  if ($cloneChoice -eq 'Y' -or $cloneChoice -eq 'y') {
    Write-Host "Cloning the repository from $RepoUrl into the current directory"
    $cloneOptions = ""
    $depthChoice = Read-Host -Prompt "Do you want [C]omplete or [S]hallow clone?"
    if ($depthChoice -ne 'C' -and $depthChoice -ne 'c') {
      $cloneOptions = "--depth=1"
    }

    $gitPath = "C:\Program Files\Git\bin\git.exe"
    if (-Not (Test-Path $gitPath)) {
      Write-ErrorAndExit "Git not found at $gitPath. Git installation may have failed."
    }
    Write-Host "$gitPath clone $RepoUrl $cloneOptions"
    & $gitPath clone $RepoUrl $cloneOptions
    if ($LASTEXITCODE -ne 0) {
      Write-ErrorAndExit "Git clone failed with exit code $LASTEXITCODE"
    }
  }
}

Function Install-IntelliJ {
  Install-ChocoPackage -PackageName "intellijidea-community" -ExecutableName "idea64"

  $ideaPath = Get-ChildItem -Path "C:\Program Files\JetBrains" -Filter idea64.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
  if (-Not $ideaPath) {
    Write-ErrorAndExit "Could not find idea64.exe in 'C:\Program Files\JetBrains'. IntelliJ installation may have failed."
  }

  Write-Host "Installing Bazel plugin..."
  & $ideaPath installPlugins "com.google.idea.bazel.ijwb"
  Write-Host "Installing google-java-format plugin..."
  & $ideaPath installPlugins "google-java-format"

  Write-Host "Setting up Java Format IntelliJ plugin"

  $ideaDirectory = Split-Path -Path $ideaPath -Parent
  $intelliJInstallationFolder = Split-Path -Path $ideaDirectory -Parent
  $fullVersion = (Split-Path -Path $intelliJInstallationFolder -Leaf) -replace "IntelliJ IDEA Community Edition ", ""
  $intelliJVersionName = "IdeaIC" + (($fullVersion -split '\.')[0,1] -join '.')
  $ideaDataPath = Join-Path -Path $env:APPDATA -ChildPath "JetBrains\$intelliJVersionName"

  try {
    if (-not (Test-Path -Path $ideaDataPath)) {
      New-Item -ItemType Directory -Path $ideaDataPath -Force | Out-Null
    }

    $vmOptionsFilePath = Join-Path -Path $ideaDataPath -ChildPath "idea64.exe.vmoptions"
    if (-not (Test-Path -Path $vmOptionsFilePath)) {
      New-Item -ItemType File -Path $vmOptionsFilePath | Out-Null
    }
    $linesToAdd = @(
      "--add-exports=jdk.compiler/com.sun.tools.javac.api=ALL-UNNAMED",
      "--add-exports=jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED",
      "--add-exports=jdk.compiler/com.sun.tools.javac.file=ALL-UNNAMED",
      "--add-exports=jdk.compiler/com.sun.tools.javac.parser=ALL-UNNAMED",
      "--add-exports=jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED",
      "--add-exports=jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED"
    )
    Add-Content -Path $vmOptionsFilePath -Value $linesToAdd
  } catch {
    Write-Host "WARNING: Failed to configure IntelliJ VM options: $_" -ForegroundColor Yellow
  }
}

Write-Host "Set Execution Policy for future processes"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -ErrorAction SilentlyContinue

Write-Host "Enable Developer Mode"
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"

Write-Host "Install Chocolatey if not already installed"
if (-Not (Get-Command choco -ErrorAction SilentlyContinue)) {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } catch {
        Write-ErrorAndExit "Failed to install Chocolatey: $_"
    }
    if (-Not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit "Chocolatey installation completed but 'choco' command not found. Try restarting PowerShell."
    }
}

Install-JDK17
Set-JavaEnvironmentVariable
Install-ChocoPackage -PackageName "git" -ExecutableName "git"
Install-ChocoPackage -PackageName "bazelisk" -ExecutableName "bazel"
Install-ChocoPackage -PackageName "msys2" -ExecutableName "C:\tools\msys64\usr\bin\bash.exe" -AdditionalParams "--params '/InstallDir=C:\tools\msys64'"
Add-ToPath -PathToAdd "C:\tools\msys64\usr\bin"
Update-EnvironmentVariable -VariableName "BAZEL_SH" -Value "C:\tools\msys64\usr\bin\bash.exe"
Install-ChocoPackage -PackageName "visualstudio2022community" -ExecutableName "devenv"

Start-Process "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
Read-Host -Prompt "Install C++ in Visual Studio then Press Enter to continue"

$bazelVcPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC"
if (-Not (Test-Path $bazelVcPath)) {
  Write-ErrorAndExit "Visual Studio VC path not found at $bazelVcPath. Ensure C++ workload was installed."
}
Update-EnvironmentVariable -VariableName "BAZEL_VC" -Value $bazelVcPath

$vcToolsBasePath = "$bazelVcPath\Tools\MSVC"
if (-Not (Test-Path $vcToolsBasePath)) {
  Write-ErrorAndExit "MSVC Tools not found at $vcToolsBasePath. Ensure C++ workload was installed in Visual Studio."
}
$vcToolsPath = Get-ChildItem -Path $vcToolsBasePath | Sort-Object Name -Descending | Select-Object -First 1
if (-Not $vcToolsPath) {
  Write-ErrorAndExit "No MSVC toolchain versions found in $vcToolsBasePath"
}
$vcToolsVersion = $vcToolsPath.Name
Update-EnvironmentVariable -VariableName "BAZEL_VC_FULL_VERSION" -Value $vcToolsVersion

Clone-Repository -RepoUrl "https://github.com/SeleniumHQ/selenium.git"

$longPathSupport = Read-Host "Do you want to change settings to better manage long file paths (recommended) (Y/N)"
if ($longPathSupport -eq 'Y' -or $longPathSupport -eq 'y')
{
  Write-Host "Enable UNC Path support"
  reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Command Processor" /t REG_DWORD /f /v "DisableUNCCheck" /d "1"

  Write-Host "Enable Long Path support"
  reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\FileSystem" /t REG_DWORD /f /v "LongPathsEnabled" /d "1"

  Write-Host "Enable creating short name versions of long file paths"
  fsutil 8dot3name set 0

  Write-Host "Set bazel output to C:/tmp instead of nested inside project directory"
  $currentDirectory = Get-Location
  $filePath = [System.IO.Path]::Combine($currentDirectory, "selenium/.bazelrc.windows.local")
  $text = "startup --output_user_root=C:/tmp"
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($filePath, $text, $encoding)
}

$intelliJChoice = Read-Host "Do you want to install and setup IntelliJ (Y/N)"
if ($intelliJChoice -eq 'Y' -or $intelliJChoice -eq 'y')
{
  Install-IntelliJ
}

$restartChoice = Read-Host "Do you want to restart the computer now? (Y/N)"
if ($restartChoice -eq 'Y' -or $restartChoice -eq 'y') {
  Restart-Computer
}
