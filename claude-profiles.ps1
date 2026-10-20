<#
.SYNOPSIS
  Run several signed-in profiles of an Electron desktop app (Claude Desktop by
  default) side by side on Windows, each with its own Start Menu shortcut.

.DESCRIPTION
  Each shortcut starts the app with its own --user-data-dir, so every profile
  keeps its own login, history and settings. The app itself is never modified.

  EXPERIMENTAL: this script has not been tested on Windows yet.

.EXAMPLE
  .\claude-profiles.ps1 add Work
  .\claude-profiles.ps1 list
  .\claude-profiles.ps1 launch Work
  .\claude-profiles.ps1 remove Work -Purge
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('add', 'list', 'launch', 'remove', 'doctor', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Label,

    # Executable to launch. Default: auto-detected Claude Desktop.
    [string]$AppPath,
    # Profile folder. Default: %APPDATA%\<app name>-<label>
    [string]$DataDir,
    # Where shortcuts are written. Default: the Start Menu programs folder.
    [string]$Dest,
    # Shortcut icon (path, or "path,index"). Default: the app's own icon.
    [string]$Icon,
    # With remove: also delete the profile folder (asks first).
    [switch]$Purge,
    # Skip the confirmation prompt for -Purge.
    [switch]$Yes,
    # Print what would happen without changing anything.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Tool = 'claude-profiles'
$Version = '0.1.0'
$DefaultAppName = 'Claude'
$Marker = "${Tool}:"   # prefix of the shortcut description that marks our shortcuts

function Fail([string]$Message) {
    [Console]::Error.WriteLine("${Tool}: $Message")
    exit 1
}

function Show-Usage {
    @"
$Tool $Version: run several signed-in profiles of a desktop app side by side

Usage:
  .\$Tool.ps1 add <label> [-AppPath PATH] [-DataDir PATH] [-Dest DIR] [-Icon PATH] [-DryRun]
  .\$Tool.ps1 list [-Dest DIR]
  .\$Tool.ps1 launch <label>
  .\$Tool.ps1 remove <label> [-Purge] [-Yes] [-DryRun]
  .\$Tool.ps1 doctor

Labels may contain letters, digits, '-' and '_'.
"@
}

function Test-Label([string]$Value) {
    if ($Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$') {
        Fail "invalid label '$Value': use letters, digits, '-' and '_' (max 32 characters)"
    }
}

function Find-App {
    $candidates = @()
    try {
        $pkg = Get-AppxPackage -Name "*$DefaultAppName*" -ErrorAction Stop | Select-Object -First 1
        if ($pkg) { $candidates += Join-Path $pkg.InstallLocation "app\$DefaultAppName.exe" }
    } catch { }
    $candidates += Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'
    $candidates += Join-Path $env:LOCALAPPDATA "Programs\$DefaultAppName\$DefaultAppName.exe"
    $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

function Get-AppName([string]$App) {
    $n = [IO.Path]::GetFileNameWithoutExtension($App)
    $n.Substring(0, 1).ToUpper() + $n.Substring(1)
}

function Get-DefaultDest { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' }

# The folder the app uses when started without --user-data-dir.
function Get-DefaultProfileDir([string]$Name) { Join-Path $env:APPDATA $Name }

# Our shortcuts in a folder: label, path, target app and profile folder.
function Get-Launchers([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    $shell = New-Object -ComObject WScript.Shell
    Get-ChildItem -LiteralPath $Folder -Filter '*.lnk' | ForEach-Object {
        $lnk = $shell.CreateShortcut($_.FullName)
        if ($lnk.Description -like "${Marker}*") {
            $data = ''
            if ($lnk.Arguments -match '--user-data-dir="([^"]+)"') { $data = $Matches[1] }
            [pscustomobject]@{
                Label   = $lnk.Description.Substring($Marker.Length)
                Path    = $_.FullName
                App     = $lnk.TargetPath
                DataDir = $data
            }
        }
    }
}

# The main process started with this profile folder (helper processes carry
# the same flag plus --type=..., and are skipped).
function Get-ProfileProcess([string]$Data) {
    $needle = "--user-data-dir=`"$Data`""
    Get-CimInstance Win32_Process | Where-Object {
        $cl = $_.CommandLine
        $cl -and
        ($cl.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        ($cl.IndexOf('--type=', [StringComparison]::Ordinal) -lt 0)
    } | Select-Object -First 1
}

function Start-Profile([string]$App, [string]$Data) {
    $running = Get-ProfileProcess $Data
    if ($running) {
        try { (New-Object -ComObject WScript.Shell).AppActivate([int]$running.ProcessId) | Out-Null } catch { }
        Write-Host "already running (pid $($running.ProcessId))"
        return
    }
    Start-Process -FilePath $App -ArgumentList "--user-data-dir=`"$Data`""
}

function Invoke-Add {
    if (-not $Label) { Fail "add needs a label, e.g. '.\$Tool.ps1 add Work'" }
    Test-Label $Label

    $app = if ($AppPath) { $AppPath } else { Find-App }
    if (-not $app) { Fail "could not find $DefaultAppName; pass -AppPath" }
    $app = [IO.Path]::GetFullPath($app)
    if (-not (Test-Path -LiteralPath $app -PathType Leaf)) { Fail "'$app' is not a file" }

    $name = Get-AppName $app
    $data = if ($DataDir) { [IO.Path]::GetFullPath($DataDir) } else { Join-Path $env:APPDATA "$name-$Label" }
    if ($data.TrimEnd('\') -ieq (Get-DefaultProfileDir $name)) {
        Fail "'$data' is the app's own default profile; choose another -DataDir"
    }
    $folder = if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Get-DefaultDest }
    $path = Join-Path $folder "$name $Label.lnk"

    if ($DryRun) {
        Write-Host "would create launcher: $path"
        Write-Host "  app:     $app"
        Write-Host "  profile: $data"
        return
    }

    if ((Test-Path -LiteralPath $path) -and -not (Get-Launchers $folder | Where-Object { $_.Path -eq $path })) {
        Fail "'$path' exists and was not created by $Tool; refusing to overwrite it"
    }
    New-Item -ItemType Directory -Force -Path $folder | Out-Null

    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    $lnk.TargetPath = $app
    $lnk.Arguments = "--user-data-dir=`"$data`""
    $lnk.WorkingDirectory = Split-Path -Parent $app
    $lnk.Description = "${Marker}$Label"
    $lnk.IconLocation = if ($Icon) { $Icon } else { "$app,0" }
    $lnk.Save()

    Write-Host "Created: $path"
    Write-Host "Profile: $data"
    Write-Host ''
    Write-Host 'Open the shortcut and sign in to the account you want in this profile.'
    Write-Host 'If the sign-in page hands control back to the wrong window, close the other'
    Write-Host 'instance while you sign in, then start it again.'
}

function Invoke-List {
    $folder = if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Get-DefaultDest }
    $found = $false
    foreach ($l in Get-Launchers $folder) {
        $found = $true
        $proc = Get-ProfileProcess $l.DataDir
        $status = if ($proc) { "running ($($proc.ProcessId))" } else { 'stopped' }
        Write-Host $l.Label
        Write-Host "  status:   $status"
        Write-Host "  launcher: $($l.Path)"
        Write-Host "  app:      $($l.App)"
        Write-Host "  profile:  $($l.DataDir)"
    }
    if (-not $found) { Write-Host "no launchers found in $folder" }
}

function Invoke-Launch {
    if (-not $Label) { Fail 'launch needs a label' }
    $folder = if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Get-DefaultDest }
    $l = Get-Launchers $folder | Where-Object { $_.Label -ceq $Label } | Select-Object -First 1
    if (-not $l) { Fail "no launcher with label '$Label' in $folder" }
    Start-Profile $l.App $l.DataDir
}

# Refuses anything that does not look like a dedicated profile folder.
function Test-SafeToPurge([string]$Dir, [string]$App) {
    if (-not [IO.Path]::IsPathRooted($Dir)) { return $false }
    $full = [IO.Path]::GetFullPath($Dir).TrimEnd('\')
    if ($full -ne $Dir.TrimEnd('\')) { return $false }
    if ($full.Split('\').Count -lt 4) { return $false }
    foreach ($protected in @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, (Get-DefaultProfileDir (Get-AppName $App)))) {
        if ($protected -and ($full -ieq $protected.TrimEnd('\'))) { return $false }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
    -not ((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Invoke-Remove {
    if (-not $Label) { Fail 'remove needs a label' }
    $folder = if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Get-DefaultDest }
    $matches_ = @(Get-Launchers $folder | Where-Object { $_.Label -ceq $Label })
    if ($matches_.Count -eq 0) { Fail "no launcher with label '$Label' in $folder" }

    foreach ($l in $matches_) {
        if ($DryRun) {
            Write-Host "would remove launcher: $($l.Path)"
            if ($Purge) { Write-Host "would delete profile:  $($l.DataDir)" }
            continue
        }
        if ($Purge) {
            if (Get-ProfileProcess $l.DataDir) { Fail "profile '$Label' is running; close it before -Purge" }
            if (-not (Test-SafeToPurge $l.DataDir $l.App)) {
                Fail "refusing to purge '$($l.DataDir)': it does not look like a dedicated profile folder"
            }
            if (-not $Yes) {
                $answer = Read-Host "This permanently deletes the profile folder:`n  $($l.DataDir)`nType the label ($Label) to confirm"
                if ($answer -cne $Label) { Fail 'cancelled; nothing was deleted' }
            }
        }
        Remove-Item -LiteralPath $l.Path -Force
        Write-Host "removed launcher: $($l.Path)"
        if ($Purge) {
            Remove-Item -LiteralPath $l.DataDir -Recurse -Force
            Write-Host "deleted profile:  $($l.DataDir)"
        } else {
            Write-Host "kept profile:     $($l.DataDir)"
        }
    }
}

function Invoke-Doctor {
    Write-Host "$Tool $Version"
    Write-Host "platform:      windows (PowerShell $($PSVersionTable.PSVersion))"
    Write-Host "launchers in:  $(if ($Dest) { [IO.Path]::GetFullPath($Dest) } else { Get-DefaultDest })"
    $app = Find-App
    if ($app) {
        Write-Host "detected app:  $app"
        Write-Host "default data:  $(Get-DefaultProfileDir (Get-AppName $app))"
    } else {
        Write-Host 'detected app:  none (pass -AppPath to add)'
    }
}

switch ($Command) {
    'add'    { Invoke-Add }
    'list'   { Invoke-List }
    'launch' { Invoke-Launch }
    'remove' { Invoke-Remove }
    'doctor' { Invoke-Doctor }
    default  { Show-Usage }
}
