<#
.SYNOPSIS
Checks variant selection, binary-header rejection, and junction-preserving package source contracts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

$all = @(Get-CanvasStagingSelection)
if ($all.Count -ne $Global:ModuleVariants.Count) {
  throw 'Default package selection must include every sharedConfig.ps1 variant.'
}
$canvas = @(Get-CanvasStagingSelection -VariantKeys 'CANVAS')
if ($canvas.Count -ne 1 -or $canvas[0].VariantKey -cne 'CANVAS') {
  throw 'Explicit Canvas package selection failed.'
}
foreach ($badKeys in @(@('UNKNOWN'), @('CANVAS', 'CANVAS'))) {
  $caught = $false
  try { [void](Get-CanvasStagingSelection -VariantKeys $badKeys) } catch { $caught = $true }
  if (!$caught) { throw "Invalid package variant selection was accepted: $($badKeys -join ', ')" }
}

$packageSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'createPackages.ps1') -Raw
foreach ($contract in @(
  '. (Join-Path $PSScriptRoot ''sharedConfig.ps1'') -SkipEnvironment',
  '$selectedVariants = @(Get-CanvasStagingSelection -VariantKeys $VariantKeys)',
  '$stagingItem.LinkType -eq ''Junction''',
  'installed package must be empty or contain exactly the candidate ESM and BA2 file set.',
  '[System.IO.File]::Move($temporaryPath, $destinationPath, $true)',
  'prior ESM/BA2 files were restored without replacing their directory or Junction'
)) {
  if (!$packageSource.Contains($contract)) {
    throw "Missing package safety contract: $contract"
  }
}
foreach ($forbiddenContract in @(
  'Remove-Item -LiteralPath $operation.InstallPath -Recurse',
  'Move-Item -LiteralPath $operation.InstallPath',
  'Move-Item -LiteralPath $operation.CandidatePath -Destination $operation.InstallPath',
  'Main_XBox.ba2',
  'Main_PS.ba2',
  '-compression=Default'
)) {
  if ($packageSource.Contains($forbiddenContract)) {
    throw "Package source retained a destructive or unsupported contract: $forbiddenContract"
  }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('canvas-artifact-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
try {
  $pointer = [Text.Encoding]::UTF8.GetBytes("version https://git-lfs.github.com/spec/v1`noid sha256:012345`nsize 4096`n")
  $rejections = 0
  foreach ($extension in @('esm', 'ba2')) {
    foreach ($fixture in @(
      @{ Name = 'pointer'; Bytes = $pointer },
      @{ Name = 'empty'; Bytes = [byte[]]::new(0) },
      @{ Name = 'truncated'; Bytes = [byte[]]::new(8) },
      @{ Name = 'wrong-magic'; Bytes = [byte[]]::new(64) }
    )) {
      $path = Join-Path $fixtureRoot ($fixture.Name + '.' + $extension)
      [System.IO.File]::WriteAllBytes($path, $fixture.Bytes)
      $rejected = $false
      try { Assert-CanvasArtifactHeader -Path $path } catch { $rejected = $true }
      if (!$rejected) { throw "Invalid binary was accepted: $path" }
      $rejections += 1
    }
  }
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

$assemblyRejected = $false
try { & (Join-Path $PSScriptRoot 'SpriggitAssembleDatabaseFromYaml.ps1') } catch { $assemblyRejected = $_.Exception.Message -like 'Spriggit assembly is disabled*' }
if (!$assemblyRejected) { throw 'Spriggit assembly did not fail closed.' }

Write-Output "Packaging contracts passed: shared variant selection, junction-preserving child-file replacement, eight binary rejections, and disabled Spriggit assembly."
