<#
.SYNOPSIS
Exercises the current-input admission functions for Papyrus, Canvas movies, Player HUD, and Ship HUD evidence.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'sharedConfig.ps1') -SkipEnvironment
. (Join-Path $PSScriptRoot 'sharedCanvas.ps1')

function Assert-TestRejected {
  param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Description)
  $caught = $false
  try { & $Action } catch { $caught = $true }
  if (!$caught) { throw "$Description was accepted." }
}

function Copy-TestObject {
  param([Parameter(Mandatory = $true)][object]$Value)
  return ($Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testBase = Join-Path $repositoryRoot '.work\canvas\build-remediation-tests'
$fixtureRoot = Join-Path $testBase ('evidence-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
try {
  $example = @(Get-ModuleVariants -VariantKeys 'EXAMPLE')[0]
  foreach ($relativePath in @(
    'Tools/compileScripts.ps1',
    'Tools/buildScaleform.ps1',
    'Tools/sharedConfig.ps1',
    'Tools/sharedCanvas.ps1',
    'Tools/sharedCanvasBuildEvidence.ps1',
    'Scaleform/canvas/canvas-matrix.psd1'
  )) {
    $fixturePath = Join-Path $fixtureRoot $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fixturePath) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $relativePath) -Destination $fixturePath
  }
  $papyrusSource = Join-Path $fixtureRoot 'Papyrus\Venworks\Canvas\ExampleRegistrar.psc'
  $papyrusOutput = Join-Path $fixtureRoot 'scripts\Venworks\Canvas\ExampleRegistrar.pex'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $papyrusSource), (Split-Path -Parent $papyrusOutput) | Out-Null
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\ExampleRegistrar.psc') -Destination $papyrusSource
  [System.IO.File]::WriteAllBytes($papyrusOutput, [Text.Encoding]::UTF8.GetBytes('compiled-example'))
  $compileToolchain = [pscustomobject]@{
    Compiler = [pscustomobject]@{ Key = 'PapyrusCompiler'; Path = 'PapyrusCompiler.exe'; Sha256 = '1' * 64 }
    CompilerVersion = 'fixture'
    Flags = [pscustomobject]@{ Key = 'PapyrusFlags'; Path = 'flags.flg'; Sha256 = '2' * 64 }
    VenworksCoreRevision = 'fixture-core'
    VenworksCoreSources = @([pscustomobject]@{ Key = 'core.psc'; Path = 'core.psc'; Sha256 = '3' * 64 })
    ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $fixtureRoot -Pipeline Papyrus)
  }
  $compileEvidence = [pscustomobject]@{
    Schema = 'VWCANVAS_SCRIPTS/2'
    Toolchain = $compileToolchain
    Scripts = @([pscustomobject]@{
      VariantKeys = @('EXAMPLE')
      Source = 'Venworks/Canvas/ExampleRegistrar.psc'
      SourceSha256 = Get-CanvasFileSha256 -Path $papyrusSource
      Output = 'Venworks/Canvas/ExampleRegistrar.pex'
      Sha256 = Get-CanvasFileSha256 -Path $papyrusOutput
    })
  }
  Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain -ValidateAllRows
  [System.IO.File]::AppendAllText($papyrusSource, 'source-drift')
  Assert-TestRejected -Description 'Papyrus source drift' -Action { Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'Papyrus\Venworks\Canvas\ExampleRegistrar.psc') -Destination $papyrusSource -Force
  [System.IO.File]::AppendAllText($papyrusOutput, 'output-drift')
  Assert-TestRejected -Description 'Papyrus output drift' -Action { Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }
  [System.IO.File]::WriteAllBytes($papyrusOutput, [Text.Encoding]::UTF8.GetBytes('compiled-example'))
  $wrongCompileToolchain = Copy-TestObject $compileToolchain
  $wrongCompileToolchain.Flags.Sha256 = '4' * 64
  Assert-TestRejected -Description 'Papyrus compiler flags drift' -Action { Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $wrongCompileToolchain }
  $compileBuilderPath = Join-Path $fixtureRoot 'Tools\compileScripts.ps1'
  $compileBuilderBytes = [System.IO.File]::ReadAllBytes($compileBuilderPath)
  $compileBuilderText = [System.IO.File]::ReadAllText($compileBuilderPath)
  if (!$compileBuilderText.Contains('-optimize')) { throw 'Real copied Papyrus builder optimization switch was not found.' }
  [System.IO.File]::WriteAllText($compileBuilderPath, $compileBuilderText.Replace('-optimize', '-no-optimize'))
  $changedCompileImplementation = Copy-TestObject $compileToolchain
  $changedCompileImplementation.ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $fixtureRoot -Pipeline Papyrus)
  Assert-TestRejected -Description 'Papyrus first-party builder drift' -Action { Assert-CanvasCompileEvidence -Evidence $compileEvidence -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $changedCompileImplementation }
  [System.IO.File]::WriteAllBytes($compileBuilderPath, $compileBuilderBytes)
  $missingCompileImplementation = Copy-TestObject $compileEvidence
  $missingCompileImplementation.Toolchain.ImplementationFiles = @($missingCompileImplementation.Toolchain.ImplementationFiles | Select-Object -Skip 1)
  Assert-TestRejected -Description 'Missing Papyrus implementation evidence row' -Action { Assert-CanvasCompileEvidence -Evidence $missingCompileImplementation -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }
  $duplicateCompileImplementation = Copy-TestObject $compileEvidence
  $duplicateCompileImplementation.Toolchain.ImplementationFiles = @($duplicateCompileImplementation.Toolchain.ImplementationFiles) + @($duplicateCompileImplementation.Toolchain.ImplementationFiles[0])
  Assert-TestRejected -Description 'Duplicate Papyrus implementation evidence row' -Action { Assert-CanvasCompileEvidence -Evidence $duplicateCompileImplementation -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }
  $duplicateCompile = Copy-TestObject $compileEvidence
  $duplicateCompile.Scripts = @($duplicateCompile.Scripts) + @($duplicateCompile.Scripts)
  Assert-TestRejected -Description 'Duplicate Papyrus evidence row' -Action { Assert-CanvasCompileEvidence -Evidence $duplicateCompile -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }
  $wrongOutputCompile = Copy-TestObject $compileEvidence
  $wrongOutputCompile.Scripts[0].Output = 'wrong.pex'
  Assert-TestRejected -Description 'Wrong canonical Papyrus output name' -Action { Assert-CanvasCompileEvidence -Evidence $wrongOutputCompile -RepositoryRoot $fixtureRoot -OutputDirectory (Join-Path $fixtureRoot 'scripts') -Variants @($example) -Toolchain $compileToolchain }

  $canvasRoot = Join-Path $fixtureRoot 'Scaleform\canvas'
  $manifestPath = Join-Path $canvasRoot 'build\example.build.xml'
  $actionScriptPath = Join-Path $canvasRoot 'actionscript\CanvasExample.as'
  $movieDirectory = Join-Path $fixtureRoot 'movies'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestPath), (Split-Path -Parent $actionScriptPath), $movieDirectory | Out-Null
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'Scaleform\canvas\build\example.build.xml') -Destination $manifestPath
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'Scaleform\canvas\actionscript\CanvasExample.as') -Destination $actionScriptPath
  $moviePath = Join-Path $movieDirectory 'CanvasExample.swf'
  [System.IO.File]::WriteAllBytes($moviePath, [Text.Encoding]::UTF8.GetBytes('canvas-movie'))
  $scaleformToolchain = [pscustomobject]@{
    VwHudRevision = 'fixture-vwhud'
    Files = @([pscustomobject]@{ Key = 'Compiler'; Path = 'compiler'; Sha256 = '5' * 64 })
    ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $fixtureRoot -Pipeline Scaleform)
  }
  $movieEvidence = [pscustomobject]@{
    Schema = 'VWCANVAS_SCALEFORM_MOVIES/2'
    Toolchain = $scaleformToolchain
    Movies = @([pscustomobject]@{
      VariantKey = 'EXAMPLE'; Name = 'example'; Role = 'consumer'; OutputFile = 'CanvasExample.swf'; Sha256 = Get-CanvasFileSha256 -Path $moviePath
      Manifest = 'build/example.build.xml'; ManifestSha256 = Get-CanvasFileSha256 -Path $manifestPath
      Source = 'actionscript/CanvasExample.as'; SourceSha256 = Get-CanvasFileSha256 -Path $actionScriptPath
      ClassInventory = @('CanvasExample'); BuildPasses = 2
    })
  }
  Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $scaleformToolchain -ValidateAllRows
  foreach ($mutation in @(
    @{ Name = 'ActionScript source drift'; Path = $actionScriptPath },
    @{ Name = 'Canvas manifest drift'; Path = $manifestPath },
    @{ Name = 'Canvas output drift'; Path = $moviePath }
  )) {
    $bytes = [System.IO.File]::ReadAllBytes($mutation.Path)
    [System.IO.File]::AppendAllText($mutation.Path, 'drift')
    Assert-TestRejected -Description $mutation.Name -Action { Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $scaleformToolchain }
    [System.IO.File]::WriteAllBytes($mutation.Path, $bytes)
  }
  $wrongMovieToolchain = Copy-TestObject $scaleformToolchain
  $wrongMovieToolchain.Files[0].Sha256 = '6' * 64
  Assert-TestRejected -Description 'Scaleform toolchain drift' -Action { Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $wrongMovieToolchain }
  $sharedBuilderPath = Join-Path $fixtureRoot 'Tools\sharedCanvas.ps1'
  $sharedBuilderBytes = [System.IO.File]::ReadAllBytes($sharedBuilderPath)
  $sharedBuilderText = [System.IO.File]::ReadAllText($sharedBuilderPath)
  if (!$sharedBuilderText.Contains("'-compiler.optimize=true'")) { throw 'Real copied Canvas helper optimization option was not found.' }
  [System.IO.File]::WriteAllText($sharedBuilderPath, $sharedBuilderText.Replace("'-compiler.optimize=true'", "'-compiler.optimize=false'"))
  $changedSharedImplementation = Copy-TestObject $scaleformToolchain
  $changedSharedImplementation.ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $fixtureRoot -Pipeline Scaleform)
  Assert-TestRejected -Description 'Scaleform first-party shared helper drift' -Action { Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $changedSharedImplementation }
  [System.IO.File]::WriteAllBytes($sharedBuilderPath, $sharedBuilderBytes)
  $scaleformBuilderPath = Join-Path $fixtureRoot 'Tools\buildScaleform.ps1'
  [System.IO.File]::AppendAllText($scaleformBuilderPath, '# builder drift')
  $changedScaleformBuilder = Copy-TestObject $scaleformToolchain
  $changedScaleformBuilder.ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $fixtureRoot -Pipeline Scaleform)
  Assert-TestRejected -Description 'Scaleform first-party entry-point drift' -Action { Assert-CanvasMovieEvidence -Evidence $movieEvidence -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $changedScaleformBuilder }
  foreach ($case in @('missing', 'duplicate', 'wrong-name', 'extra')) {
    $candidate = Copy-TestObject $movieEvidence
    switch ($case) {
      'missing' { $candidate.Movies = @() }
      'duplicate' { $candidate.Movies = @($candidate.Movies) + @($candidate.Movies) }
      'wrong-name' { $candidate.Movies[0].OutputFile = 'Wrong.swf' }
      'extra' { $extra = Copy-TestObject $candidate.Movies[0]; $extra.VariantKey = 'UNKNOWN'; $candidate.Movies = @($candidate.Movies) + @($extra) }
    }
    Assert-TestRejected -Description "Canvas evidence $case row case" -Action { Assert-CanvasMovieEvidence -Evidence $candidate -RepositoryRoot $fixtureRoot -MoviesDirectory $movieDirectory -Variants @($example) -Toolchain $scaleformToolchain -ValidateAllRows }
  }

  $hudRepository = Join-Path $fixtureRoot 'hud-repository'
  $playerRoot = Join-Path $fixtureRoot 'player-output'
  $playerBuild = Join-Path $fixtureRoot 'Scaleform\canvas\build'
  $playerPatch = Join-Path $fixtureRoot 'Scaleform\canvas\patches\player-hud-watch-disabled.xml'
  $hudCompiler = Join-Path $hudRepository 'Tools\compileScaleform.ps1'
  New-Item -ItemType Directory -Force -Path $playerRoot, $playerBuild, (Split-Path -Parent $playerPatch), (Split-Path -Parent $hudCompiler) | Out-Null
  [System.IO.File]::WriteAllText($playerPatch, 'patch')
  [System.IO.File]::WriteAllText($hudCompiler, 'compiler')
  $componentNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  $definitionRows = [System.Collections.Generic.List[string]]::new()
  $playerMovies = [System.Collections.Generic.List[object]]::new()
  foreach ($name in $componentNames) {
    $path = Join-Path $playerRoot $name
    [System.IO.File]::WriteAllBytes($path, [Text.Encoding]::UTF8.GetBytes("output-$name"))
    $hash = Get-CanvasFileSha256 -Path $path
    $definitionRows.Add("    @{ File = '$name'; VanillaSha256 = '$('7' * 64)'; OutputSha256 = '$hash' }")
    $playerMovies.Add([pscustomobject]@{ File = $name; Role = 'WatchPresentationDisabled'; VanillaSha256 = '7' * 64; ExpectedSha256 = $hash; Sha256 = $hash })
  }
  $playerDefinition = Join-Path $playerBuild 'player-hud-watch.build.psd1'
  Write-CanvasUtf8WithoutBom -Path $playerDefinition -Text ("@{`n  Patch = '../patches/player-hud-watch-disabled.xml'`n  Movies = @(`n" + [string]::Join("`n", $definitionRows) + "`n  )`n}`n")
  $playerMatrix = @{ VwHudFixture = @{ Revision = 'fixture-vwhud'; PlayerHudMovies = @() } }
  foreach ($name in @('hudmenu.gfx', 'hudmenu.swf', 'hudmenu_lrg.gfx', 'hudmenu_lrg.swf')) {
    $source = "Staging/$name"
    $sourcePath = Join-Path $hudRepository $source
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sourcePath) | Out-Null
    [System.IO.File]::WriteAllBytes($sourcePath, [Text.Encoding]::UTF8.GetBytes("host-$name"))
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $playerRoot $name)
    $playerMatrix.VwHudFixture.PlayerHudMovies += @{ Source = $source; Target = "Interface/$name" }
    $hash = Get-CanvasFileSha256 -Path $sourcePath
    $playerMovies.Add([pscustomobject]@{ File = $name; Role = 'PlayerHudHost'; Source = $source; SourceSha256 = $hash; Sha256 = $hash })
  }
  $playerEvidencePath = Join-Path $playerRoot 'build-evidence.json'
  $playerInputs = @(
    (Get-CanvasEvidenceFileRow -Key 'Definition' -Path $playerDefinition -DisplayPath 'Scaleform/canvas/build/player-hud-watch.build.psd1'),
    (Get-CanvasEvidenceFileRow -Key 'Patch' -Path $playerPatch -DisplayPath ([System.IO.Path]::GetRelativePath($fixtureRoot, $playerPatch))),
    (Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $hudCompiler -DisplayPath 'Tools/compileScaleform.ps1')
  )
  $playerEvidence = [pscustomobject]@{ Schema = 'VWCANVAS_PLAYER_HUD_BUILD/2'; PinnedOutputs = $true; VwHudRevision = 'fixture-vwhud'; Inputs = $playerInputs; Movies = @($playerMovies) }
  Write-CanvasUtf8WithoutBom -Path $playerEvidencePath -Text (($playerEvidence | ConvertTo-Json -Depth 8) + "`n")
  Assert-CanvasPlayerHudEvidence -Evidence $playerEvidence -RepositoryRoot $fixtureRoot -VwHudRepositoryPath $hudRepository -PlayerDirectory $playerRoot -Matrix $playerMatrix
  foreach ($mutation in @(
    @{ Name = 'Player definition drift'; Path = $playerDefinition }, @{ Name = 'Player patch drift'; Path = $playerPatch },
    @{ Name = 'Player compiler drift'; Path = $hudCompiler }, @{ Name = 'Player host source drift'; Path = (Join-Path $hudRepository 'Staging\hudmenu.swf') },
    @{ Name = 'Player output drift'; Path = (Join-Path $playerRoot 'playerhudcomponents.swf') }
  )) {
    $bytes = [System.IO.File]::ReadAllBytes($mutation.Path)
    [System.IO.File]::AppendAllText($mutation.Path, 'drift')
    Assert-TestRejected -Description $mutation.Name -Action { Assert-CanvasPlayerHudEvidence -Evidence $playerEvidence -RepositoryRoot $fixtureRoot -VwHudRepositoryPath $hudRepository -PlayerDirectory $playerRoot -Matrix $playerMatrix }
    [System.IO.File]::WriteAllBytes($mutation.Path, $bytes)
  }

  $shipRoot = Join-Path $fixtureRoot 'ship-output'
  $shipPatch = Join-Path $fixtureRoot 'Scaleform\canvas\patches\spaceship-hud-auxiliary-loader.xml'
  New-Item -ItemType Directory -Force -Path $shipRoot | Out-Null
  [System.IO.File]::WriteAllText($shipPatch, 'ship-patch')
  $shipMatrix = @{ VwHudFixture = @{ Revision = 'fixture-vwhud'; ShipCompilerFile = 'Tools/compileScaleform.ps1' } }
  $shipInputs = [System.Collections.Generic.List[object]]::new()
  $shipMovies = [System.Collections.Generic.List[object]]::new()
  foreach ($definition in @(
    @{ Manifest = 'spaceshiphudmenu.build.xml'; File = 'spaceshiphudmenu.swf'; HashPrefix = 'normal' },
    @{ Manifest = 'spaceshiphudmenu-lrg.build.xml'; File = 'spaceshiphudmenu_lrg.swf'; HashPrefix = 'large' }
  )) {
    $output = Join-Path $shipRoot $definition.File
    [System.IO.File]::WriteAllBytes($output, [Text.Encoding]::UTF8.GetBytes("ship-$($definition.File)"))
    $outputHash = Get-CanvasFileSha256 -Path $output
    $vanillaFile = "$($definition.HashPrefix).vanilla.sha256"
    $expectedFile = "$($definition.HashPrefix).expected.sha256"
    $manifest = Join-Path $playerBuild $definition.Manifest
    Write-CanvasUtf8WithoutBom -Path (Join-Path $playerBuild $vanillaFile) -Text (('8' * 64) + "  $($definition.File)`n")
    Write-CanvasUtf8WithoutBom -Path (Join-Path $playerBuild $expectedFile) -Text ($outputHash + "  $($definition.File)`n")
    Write-CanvasUtf8WithoutBom -Path $manifest -Text ("<scaleformBuild outputFile=`"$($definition.File)`" vanillaHashFile=`"$vanillaFile`" expectedHashFile=`"$expectedFile`" />`n")
    $shipInputs.Add((Get-CanvasEvidenceFileRow -Key "Manifest/$($definition.Manifest)" -Path $manifest -DisplayPath "Scaleform/canvas/build/$($definition.Manifest)"))
    $shipInputs.Add((Get-CanvasEvidenceFileRow -Key "Hash/$vanillaFile" -Path (Join-Path $playerBuild $vanillaFile) -DisplayPath "Scaleform/canvas/build/$vanillaFile"))
    $shipInputs.Add((Get-CanvasEvidenceFileRow -Key "Hash/$expectedFile" -Path (Join-Path $playerBuild $expectedFile) -DisplayPath "Scaleform/canvas/build/$expectedFile"))
    $shipMovies.Add([pscustomobject]@{ File = $definition.File; Manifest = "Scaleform/canvas/build/$($definition.Manifest)"; VanillaSha256 = '8' * 64; ExpectedSha256 = $outputHash; Sha256 = $outputHash })
  }
  $shipInputs.Add((Get-CanvasEvidenceFileRow -Key 'Patch' -Path $shipPatch -DisplayPath 'Scaleform/canvas/patches/spaceship-hud-auxiliary-loader.xml'))
  $shipInputs.Add((Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $hudCompiler -DisplayPath 'Tools/compileScaleform.ps1'))
  $shipEvidencePath = Join-Path $shipRoot 'build-evidence.json'
  $shipEvidence = [pscustomobject]@{ Schema = 'VWCANVAS_SHIP_HUD_BUILD/2'; PinnedOutputs = $true; VwHudRevision = 'fixture-vwhud'; Inputs = @($shipInputs); Movies = @($shipMovies) }
  Write-CanvasUtf8WithoutBom -Path $shipEvidencePath -Text (($shipEvidence | ConvertTo-Json -Depth 8) + "`n")
  Assert-CanvasShipHudEvidence -Evidence $shipEvidence -RepositoryRoot $fixtureRoot -VwHudRepositoryPath $hudRepository -ShipDirectory $shipRoot -Matrix $shipMatrix
  foreach ($mutation in @(
    @{ Name = 'Ship manifest drift'; Path = (Join-Path $playerBuild 'spaceshiphudmenu.build.xml') },
    @{ Name = 'Ship patch drift'; Path = $shipPatch }, @{ Name = 'Ship compiler drift'; Path = $hudCompiler },
    @{ Name = 'Ship output drift'; Path = (Join-Path $shipRoot 'spaceshiphudmenu.swf') }
  )) {
    $bytes = [System.IO.File]::ReadAllBytes($mutation.Path)
    [System.IO.File]::AppendAllText($mutation.Path, 'drift')
    Assert-TestRejected -Description $mutation.Name -Action { Assert-CanvasShipHudEvidence -Evidence $shipEvidence -RepositoryRoot $fixtureRoot -VwHudRepositoryPath $hudRepository -ShipDirectory $shipRoot -Matrix $shipMatrix }
    [System.IO.File]::WriteAllBytes($mutation.Path, $bytes)
  }
}
finally {
  if (Test-Path -LiteralPath $fixtureRoot) {
    Assert-CanvasRemovalPath -Path $fixtureRoot -AllowedRoot $testBase
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
  }
}

Write-Output 'Build evidence contracts passed: current Papyrus, ActionScript, manifest, definition, patch, compiler, exact first-party builder/helper/toolchain provenance, canonical output, duplicate/missing/extra row, Player HUD eight-movie, and Ship HUD two-movie checks.'
