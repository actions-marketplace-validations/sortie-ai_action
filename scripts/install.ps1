<#
.SYNOPSIS
    Installs one Sortie release on a Windows runner.

.DESCRIPTION
    The archive is checked against a checksums.txt downloaded in this run,
    even when the archive itself comes from the cache, so a poisoned cache
    entry never reaches the run step.

    Environment: SA_TAG, SA_ARCHIVE, SA_CACHE_DIR, SA_BIN_DIR, SA_VERIFY,
    GH_TOKEN (read by gh), GITHUB_PATH, GITHUB_OUTPUT.
#>

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo    = 'sortie-ai/sortie'
$Bin     = 'sortie.exe'
$Retries = 3

function Get-RequiredEnv {
    param([Parameter(Mandatory)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) { throw "$Name is not set" }
    return $value
}

function Write-Failure {
    param([Parameter(Mandatory)][string]$Message)

    # Messages can carry exception text; escaping stops it from starting a new
    # workflow command.
    $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
    [Console]::Out.WriteLine("::error title=Sortie Action::$escaped")
}

function Add-Line {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Line
    )

    # Set-Content and Add-Content differ in BOM handling across PowerShell
    # editions, and a BOM corrupts the first entry of a runner command file.
    [System.IO.File]::AppendAllText($Path, "$Line`n", [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Download {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )

    for ($attempt = 0; ; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
            return
        }
        catch {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            if ($attempt -ge $Retries) { throw }
            Start-Sleep -Seconds (2 * ($attempt + 1))
        }
    }
}

# Hash on the checksums.txt line (each line: "<hex-sha256>  <filename>") whose
# file name equals $Name; $null when there is none.
function Get-ExpectedHash {
    param(
        [Parameter(Mandatory)][string]$SumsPath,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($line in Get-Content -LiteralPath $SumsPath) {
        $fields = $line -split '\s+', 2
        if ($fields.Count -eq 2 -and $fields[1].Trim() -ceq $Name) {
            return $fields[0].Trim()
        }
    }
    return $null
}

# A corrupt or unverifiable archive is removed so the save step can never
# cache it.
function Stop-WithRejectedArchive {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Message
    )

    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    throw $Message
}

function Expand-Binary {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -ceq $Bin } | Select-Object -First 1
        if ($null -eq $entry) { return $false }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $Destination, $true)
        return $true
    }
    finally {
        $zip.Dispose()
    }
}

function Invoke-Install {
    $tag      = Get-RequiredEnv 'SA_TAG'
    $archive  = Get-RequiredEnv 'SA_ARCHIVE'
    $cacheDir = Get-RequiredEnv 'SA_CACHE_DIR'
    $binDir   = Get-RequiredEnv 'SA_BIN_DIR'
    $verify   = Get-RequiredEnv 'SA_VERIFY'

    # The Invoke-WebRequest progress bar slows large downloads badly.
    $ProgressPreference = 'SilentlyContinue'

    $base        = "https://github.com/$Repo/releases/download/$tag"
    $archivePath = Join-Path $cacheDir $archive

    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        $partPath = "$archivePath.part"
        try {
            Invoke-Download -Url "$base/$archive" -OutFile $partPath
        }
        catch {
            throw "could not download $archive for ${tag}: $($_.Exception.Message)"
        }
        Move-Item -LiteralPath $partPath -Destination $archivePath -Force
    }

    $tempRoot = if ([string]::IsNullOrEmpty($env:RUNNER_TEMP)) { [System.IO.Path]::GetTempPath() } else { $env:RUNNER_TEMP }
    $workDir  = Join-Path $tempRoot ("sortie-install-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        $sumsPath = Join-Path $workDir 'checksums.txt'
        try {
            Invoke-Download -Url "$base/checksums.txt" -OutFile $sumsPath
        }
        catch {
            throw "could not download checksums.txt for ${tag}: $($_.Exception.Message)"
        }

        $want = Get-ExpectedHash -SumsPath $sumsPath -Name $archive
        if ([string]::IsNullOrEmpty($want)) {
            Stop-WithRejectedArchive -Path $archivePath -Message "no checksum entry for $archive"
        }
        $got = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($want -ine $got) {
            Stop-WithRejectedArchive -Path $archivePath -Message "checksum mismatch for $archive"
        }

        if ($verify -eq 'true') {
            & gh release verify-asset $tag $archivePath --repo $Repo
            if ($LASTEXITCODE -ne 0) {
                Stop-WithRejectedArchive -Path $archivePath `
                    -Message "attestation check failed for $archive; set verify-attestation to false to skip it"
            }
        }

        $extracted = Join-Path $workDir $Bin
        if (-not (Expand-Binary -ArchivePath $archivePath -Destination $extracted)) {
            Stop-WithRejectedArchive -Path $archivePath -Message "$archive does not contain $Bin"
        }

        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        $target = Join-Path $binDir $Bin
        Move-Item -LiteralPath $extracted -Destination $target -Force
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    & $target --version
    if ($LASTEXITCODE -ne 0) { throw 'the installed sortie binary does not run' }

    Add-Line -Path (Get-RequiredEnv 'GITHUB_PATH') -Line $binDir
    Add-Line -Path (Get-RequiredEnv 'GITHUB_OUTPUT') -Line "bin=$target"
}

try {
    Invoke-Install
}
catch {
    Write-Failure $_.Exception.Message
    exit 1
}
