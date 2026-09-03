<#
.SYNOPSIS
Runs isolated negative binary-header fixtures against the same checker used in normal and Committed repository validation.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConsumerDiscoveryProbe.ps1')
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('canvas-artifact-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$pointer = [Text.Encoding]::UTF8.GetBytes("version https://git-lfs.github.com/spec/v1`noid sha256:012345`nsize 4096`n")
$rejections = 0
foreach ($extension in @('esm','ba2')) {
  foreach ($fixture in @(
    @{ Name = 'pointer'; Bytes = $pointer },
    @{ Name = 'empty'; Bytes = [byte[]]::new(0) },
    @{ Name = 'truncated'; Bytes = [byte[]]::new(8) },
    @{ Name = 'wrong-magic'; Bytes = [byte[]]::new(64) }
  )) {
    $path = Join-Path $fixtureRoot ($fixture.Name + '.' + $extension)
    [System.IO.File]::WriteAllBytes($path, $fixture.Bytes)
    $rejected = $false
    try { Assert-ConsumerDiscoveryArtifactHeader -Path $path } catch { $rejected = $true }
    if (!$rejected) { throw "Invalid binary was accepted: $path" }
    $rejections += 1
  }
}
$checker = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checkRepo.ps1') -Raw
$badEsm = [byte[]]::new(64)
[Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($badEsm, 0)
[BitConverter]::GetBytes([uint32]1000).CopyTo($badEsm, 4)
$badBa2 = [byte[]]::new(64)
[Text.Encoding]::ASCII.GetBytes('BTDX').CopyTo($badBa2, 0)
[BitConverter]::GetBytes([uint32]2).CopyTo($badBa2, 4)
[Text.Encoding]::ASCII.GetBytes('GNRL').CopyTo($badBa2, 8)
[BitConverter]::GetBytes([uint32]1).CopyTo($badBa2, 12)
[BitConverter]::GetBytes([uint64]32).CopyTo($badBa2, 16)
foreach ($fixture in @(@{ Name = 'truncated-body.esm'; Bytes = $badEsm }, @{ Name = 'truncated-record-table.ba2'; Bytes = $badBa2 })) {
  $path = Join-Path $fixtureRoot $fixture.Name
  [IO.File]::WriteAllBytes($path, $fixture.Bytes)
  $rejected = $false
  try { Assert-ConsumerDiscoveryArtifactHeader -Path $path } catch { $rejected = $true }
  if (!$rejected) { throw "Invalid header with a valid signature was accepted: $path" }
  $rejections += 1
}
if (!$checker.Contains('Assert-ConsumerDiscoveryArtifactHeader -Path $artifactPath')) { throw 'checkRepo does not use the tested binary checker.' }
foreach ($file in @('compileScripts.ps1','createPackages.ps1','SpriggitDumpDatabaseToYaml.ps1','SpriggitAssembleDatabaseFromYaml.ps1')) {
  $body = Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw
  if ($body -match '(?i)\./Staging/|\.\\Staging\\|\bdeserialize\b') { throw "Legacy Staging/assembly path retained in $file." }
}
$assemblyRejected = $false
try { & (Join-Path $PSScriptRoot 'SpriggitAssembleDatabaseFromYaml.ps1') } catch { $assemblyRejected = $_.Exception.Message -like 'Spriggit assembly is disabled*' }
if (!$assemblyRejected) { throw 'Spriggit assembly did not fail closed.' }
Write-Output "Packaging negative fixtures passed: $rejections binary rejections and disabled assembly; retained at $fixtureRoot"
