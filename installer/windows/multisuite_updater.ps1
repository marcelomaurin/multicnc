param(
  [Parameter(Mandatory=$true)][string]$InstalledVersion,
  [switch]$ForceCheck
)
$ErrorActionPreference = 'Stop'
$repo = 'marcelomaurin/multicnc'
$state = Join-Path $env:LOCALAPPDATA 'MultiSuite\Updater'
$stamp = Join-Path $state 'last-check.txt'
$log = Join-Path $state 'updater.log'
New-Item -ItemType Directory -Force -Path $state | Out-Null
function Log([string]$message) {
  Add-Content -LiteralPath $log -Value ("{0:u} {1}" -f (Get-Date),$message)
}
try {
  # Only one update checker per account.
  $mutex = New-Object System.Threading.Mutex($false, 'Local\MultiSuiteGitHubUpdater')
  if (-not $mutex.WaitOne(0)) { exit 0 }
  try {
    if (-not $ForceCheck -and (Test-Path $stamp)) {
      $last = [datetime]::Parse((Get-Content $stamp -Raw))
      if ((Get-Date) -lt $last.AddHours(12)) { exit 0 }
    }
    # A failed network request can be retried at next login.
    $headers = @{ 'User-Agent'='MultiSuite-Updater'; 'Accept'='application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers -TimeoutSec 20
    if ($release.draft -or $release.prerelease) { exit 0 }
    $remoteText = ([string]$release.tag_name).TrimStart('v','V')
    if ($remoteText -notmatch '^\d+\.\d+(\.\d+){0,2}$') { throw 'Versao de release invalida' }
    $localText = $InstalledVersion.TrimStart('v','V')
    if ($localText -notmatch '^\d+\.\d+(\.\d+){0,2}$') { throw 'Versao instalada invalida' }
    $remote = [version]$remoteText
    $local = [version]$localText
    if ($remote -le $local) {
      Set-Content -LiteralPath $stamp -Value (Get-Date).ToString('o')
      exit 0
    }
    $setupAsset = @($release.assets | Where-Object { $_.name -match '^setup_multcnc_[0-9.]+\.exe$' } | Select-Object -First 1)
    $hashAsset = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS' } | Select-Object -First 1)
    if ($setupAsset.Count -ne 1 -or $hashAsset.Count -ne 1) { throw 'Release sem instalador ou SHA256SUMS' }
    $setupAsset = $setupAsset[0]; $hashAsset = $hashAsset[0]
    $tempDir = Join-Path $state ('release-' + $remoteText)
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $installer = Join-Path $tempDir $setupAsset.name
    $checksum = Join-Path $tempDir 'SHA256SUMS'
    foreach ($asset in @(@($setupAsset,$installer),@($hashAsset,$checksum))) {
      if ($asset[0].browser_download_url -notlike 'https://github.com/marcelomaurin/multicnc/releases/download/*') {
        throw 'Origem de download inesperada'
      }
      Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $asset[1] -UseBasicParsing -TimeoutSec 300
    }
    $escaped = [regex]::Escape($setupAsset.name)
    $line = Get-Content -LiteralPath $checksum | Where-Object { $_ -match ("^[a-fA-F0-9]{64}\s+\*?" + $escaped + "$") } | Select-Object -First 1
    if (-not $line) { throw 'Hash do instalador nao encontrado' }
    $expected = ($line -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw 'Falha de integridade SHA256' }
    Log "Instalador $remoteText verificado. Solicitando instalacao."
    # Inno Setup handles application shutdown and elevation as needed.
    # Not silent: preserves user control over components and UAC.
    Start-Process -FilePath $installer
    Set-Content -LiteralPath $stamp -Value (Get-Date).ToString('o')
  } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
} catch {
  Log ("Falha: " + $_.Exception.Message)
  exit 1
}
