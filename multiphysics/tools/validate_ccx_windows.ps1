param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$ExpectedSha256,
  [string]$Python = "python",
  [string]$Verifier = (Join-Path $PSScriptRoot "verify_ccx_package.py"),
  [string]$LogPath = (Join-Path $PSScriptRoot "ccx_windows_validation.log")
)
$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
function Record([string]$message) {
  $line = "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')] $message"
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
  Write-Host $line
}
try {
  Record "START zip=$([IO.Path]::GetFileName($ZipPath))"
  if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "ZIP ausente" }
  if (-not (Test-Path -LiteralPath $Verifier -PathType Leaf)) { throw "Verificador ausente" }
  & $Python $Verifier $ZipPath --sha256 $ExpectedSha256
  if ($LASTEXITCODE -ne 0) { throw "Verificacao de integridade falhou" }
  Record "PASS integridade ZIP; nao homologado para ativacao"
  Record "PENDENTE: validar procedencia, licenca, DLLs, execucao real do ccx.exe e benchmark FEM"
  exit 0
} catch {
  Record "FAIL $($_.Exception.Message)"
  exit 1
}
