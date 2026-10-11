param(
  [string]$Version = $env:VERSION,
  [ValidatePattern('^\d{3}$')][string]$SetupSeq = '007',
  [switch]$AllowDirty
)
$ErrorActionPreference = 'Stop'
if (-not $Version) { $Version = '0.07' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Set-Location -LiteralPath $root
$dist = Join-Path $root 'dist'
$app = Join-Path $dist 'app'
$bin = Join-Path $root 'bin'
function FindTool($EnvName, $Name, $Fallbacks) {
  $value = [Environment]::GetEnvironmentVariable($EnvName)
  if ($value -and (Test-Path -LiteralPath $value)) { return $value }
  foreach ($path in $Fallbacks) { if (Test-Path -LiteralPath $path) { return $path } }
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  throw "Ferramenta ausente: $Name. Configure $EnvName."
}
$env:LAZBUILD = FindTool 'LAZBUILD' 'lazbuild' @('C:\lazarus\lazbuild.exe')
$env:FPC = FindTool 'FPC' 'fpc' @('C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe')
$python = FindTool 'PYTHON' 'python' @("$env:LOCALAPPDATA\Programs\Python\Python313\python.exe")
$pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
$iscc = FindTool 'ISCC' 'iscc' @("$env:ProgramFiles\Inno Setup 7\ISCC.exe", "$pf86\Inno Setup 6\ISCC.exe")
# Publicacao exige fontes registradas; builds locais registram source_dirty=true.
if (-not $AllowDirty) {
  $status = & git status --porcelain
  if ($LASTEXITCODE -ne 0 -or $status) { throw 'A release exige uma arvore Git limpa. Para build local use -AllowDirty.' }
}
# Valida o destino antes de remover apenas o staging desta release.
if ([IO.Path]::GetFullPath($app) -ne (Join-Path $root 'dist\app')) { throw 'Staging fora da pasta esperada.' }
if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
New-Item -ItemType Directory -Force -Path $app, $bin, (Join-Path $dist 'build-logs') | Out-Null
$config = Join-Path $dist 'compiler-dependencies.cfg'
$chatgpt = if ($env:MULTICNC_CHATGPT_DIR) { $env:MULTICNC_CHATGPT_DIR } else { Join-Path (Split-Path $root) 'CHATGPT' }
$flags = @()
foreach ($folder in @('pacote\AI', 'pacote\AI Input\AISerial', 'pacote\AI Simulation\Marlin', 'pacote\AI Input\AISockets', 'pacote\AI Input\AIVirtualSerial')) {
  $path = Join-Path $chatgpt $folder
  if (Test-Path -LiteralPath $path) { $flags += "-Fu$path" }
}
[IO.File]::WriteAllLines($config, $flags)
$targets = @(
 @('multicad\src\app\multicad','multicad'),
 @('multiassembly\src\app\multiassembly','multiassembly'),
 @('multiphysics\src\app\multiphysics','multiphysics'),
 @('multicam\src\app\multicam','multicam'),
 @('multislicer\src\app\multislicer','multislicer'),
 @('makepcb\src\app\makepcb','makepcb'),
 @('makerouter\src\app\makerouter','makerouter'),
 @('routerpcb\src\app\routerpcb','routerpcb'),
 @('laserpcb\src\app\laserpcb','laserpcb'),
 @('laserart\src\app\laserart','laserart'),
 @('src\app\multicnc','multicnc'),
 @('multisuite\src\tray\multisuite_tray','multisuite_tray'),
 @('src\simucnc\simucnc','SimuCNC')
)
foreach ($target in $targets) {
  Write-Host "Compilando $($target[1])..."
  $log = Join-Path $dist ("build-logs\" + $target[1] + '.log')
  & $env:LAZBUILD '--ws=win32' "--compiler=$env:FPC" "--opt=@$config" '--build-mode=Default' ($target[0]+'.lpi') *> $log
  if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log -Tail 35; throw "Falha ao compilar $($target[1])" }
  Copy-Item -LiteralPath ($target[0]+'.exe') -Destination (Join-Path $app ($target[1]+'.exe')) -Force
}
$strip = Join-Path (Split-Path $env:FPC) 'strip.exe'
if (Test-Path -LiteralPath $strip) {
  foreach ($exe in Get-ChildItem -LiteralPath $app -Filter '*.exe') {
    & $strip '--strip-debug' $exe.FullName
    if ($LASTEXITCODE -ne 0) { throw "Falha ao reduzir $($exe.Name)" }
  }
}
& $python '-u' 'tools\verify_suite.py' console --stage $app
if ($LASTEXITCODE -ne 0) { throw 'Testes de console falharam.' }
Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $app -Recurse -Force
$manifestArgs = @('tools\release_manifest.py','--app-dir',$app,'--version',$Version,'--os','windows','--arch','amd64','--version-include',(Join-Path $dist 'version.iss'))
if (-not $AllowDirty) { $manifestArgs += '--require-clean' }
& $python @manifestArgs
if ($LASTEXITCODE -ne 0) { throw 'Falha na validacao do manifesto.' }
& (Join-Path $PSScriptRoot 'prepare_images.ps1') -Version $Version
$name = "setup_multcnc_$SetupSeq"
& $iscc "-dSetupSeq=$SetupSeq" "-dOutputExeName=$name" (Join-Path $PSScriptRoot 'multisuite.iss')
if ($LASTEXITCODE -ne 0) { throw 'Falha no Inno Setup.' }
Copy-Item -LiteralPath (Join-Path $dist "$name.exe") -Destination $bin -Force
$setup = Join-Path $root 'setup'
New-Item -ItemType Directory -Force -Path $setup | Out-Null
Copy-Item -LiteralPath (Join-Path $dist "$name.exe") -Destination $setup -Force
$blocked = @()
foreach ($target in $targets) {
  try { Copy-Item -LiteralPath (Join-Path $app ($target[1]+'.exe')) -Destination $bin -Force }
  catch { $blocked += $target[1]; Write-Warning "Feche $($target[1]) para atualizar seu executavel em bin." }
}
$hash = (Get-FileHash -LiteralPath (Join-Path $dist "$name.exe") -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText((Join-Path $dist 'SHA256SUMS'), "$hash  $name.exe" + [Environment]::NewLine)
Copy-Item -LiteralPath (Join-Path $dist 'SHA256SUMS') -Destination $setup -Force
if ($blocked.Count) { throw "Setup gerado; executaveis de bin bloqueados: $($blocked -join ', ')" }
Write-Host "Setup gerado: bin\$name.exe"
