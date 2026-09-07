$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-CanvasExactNames {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Actual,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $actualNames = @($Actual | Sort-Object)
  $expectedNames = @($Expected | Sort-Object)
  if ($actualNames.Count -ne $expectedNames.Count -or
      [string]::Join("`n", $actualNames) -cne [string]::Join("`n", $expectedNames)) {
    throw "$Description differs. Expected $([string]::Join(', ', $expectedNames)); found $([string]::Join(', ', $actualNames))."
  }
}

function Get-CanvasEvidenceFileRow {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$DisplayPath
  )

  $resolvedPath = Resolve-CanvasRequiredFile -Path $Path -Description "Evidence input '$Key'"
  return [ordered]@{
    Key = $Key
    Path = if ([string]::IsNullOrWhiteSpace($DisplayPath)) { Split-Path -Leaf $resolvedPath } else { $DisplayPath.Replace('\', '/') }
    Sha256 = Get-CanvasFileSha256 -Path $resolvedPath
  }
}

function Assert-CanvasEvidenceFileRows {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actual,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-CanvasExactNames `
    -Actual @($Actual | ForEach-Object { [string]$_.Key }) `
    -Expected @($Expected | ForEach-Object { [string]$_.Key }) `
    -Description "$Description key inventory"
  foreach ($expectedRow in @($Expected)) {
    $matchingRows = @($Actual | Where-Object { [string]$_.Key -ceq [string]$expectedRow.Key })
    if ($matchingRows.Count -ne 1 -or
        [string]$matchingRows[0].Path -cne [string]$expectedRow.Path -or
        [string]$matchingRows[0].Sha256 -cne [string]$expectedRow.Sha256) {
      throw "$Description does not match current input '$($expectedRow.Key)'."
    }
  }
}

function Get-CanvasBuildImplementationEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][ValidateSet('Papyrus', 'Scaleform')][string]$Pipeline
  )

  $entryPoint = if ($Pipeline -ceq 'Papyrus') { 'Tools/compileScripts.ps1' } else { 'Tools/buildScaleform.ps1' }
  $relativePaths = @(
    $entryPoint,
    'Tools/sharedConfig.ps1',
    'Tools/sharedCanvas.ps1',
    'Tools/sharedCanvasBuildEvidence.ps1',
    'Scaleform/canvas/canvas-matrix.psd1'
  )
  return @($relativePaths | ForEach-Object {
    Get-CanvasEvidenceFileRow -Key $_ -Path (Join-Path $RepositoryRoot $_) -DisplayPath $_
  })
}

function Get-CanvasCompileToolchainEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$CompilerPath,
    [Parameter(Mandatory = $true)][string]$FlagsPath,
    [Parameter(Mandatory = $true)][string]$VenworksCoreRepositoryPath,
    [Parameter(Mandatory = $true)][hashtable]$Matrix
  )

  $compiler = Resolve-CanvasRequiredFile -Path $CompilerPath -Description 'Papyrus compiler'
  $flags = Resolve-CanvasRequiredFile -Path $FlagsPath -Description 'Papyrus compiler flags'
  $coreRows = @($Matrix.VenworksCoreFixture.SourceFiles | ForEach-Object {
    $relativePath = [string]$_.Path
    $path = Resolve-CanvasRequiredFile -Path (Join-Path $VenworksCoreRepositoryPath $relativePath) -Description "Pinned Core source '$relativePath'"
    [ordered]@{
      Key = $relativePath.Replace('\', '/')
      Path = $relativePath.Replace('\', '/')
      Sha256 = Get-CanvasFileSha256 -Path $path
    }
  })
  return [ordered]@{
    Compiler = Get-CanvasEvidenceFileRow -Key 'PapyrusCompiler' -Path $compiler -DisplayPath (Split-Path -Leaf $compiler)
    CompilerVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($compiler).FileVersion
    Flags = Get-CanvasEvidenceFileRow -Key 'PapyrusFlags' -Path $flags -DisplayPath (Split-Path -Leaf $flags)
    VenworksCoreRevision = [string]$Matrix.VenworksCoreFixture.Revision
    VenworksCoreSources = $coreRows
    ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $RepositoryRoot -Pipeline Papyrus)
  }
}

function Assert-CanvasCompileToolchainEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Actual,
    [Parameter(Mandatory = $true)][object]$Expected
  )

  if ([string]$Actual.CompilerVersion -cne [string]$Expected.CompilerVersion -or
      [string]$Actual.VenworksCoreRevision -cne [string]$Expected.VenworksCoreRevision) {
    throw 'Papyrus compile evidence uses a different compiler version or Core revision.'
  }
  Assert-CanvasEvidenceFileRows -Actual @($Actual.Compiler) -Expected @($Expected.Compiler) -Description 'Papyrus compiler evidence'
  Assert-CanvasEvidenceFileRows -Actual @($Actual.Flags) -Expected @($Expected.Flags) -Description 'Papyrus flags evidence'
  Assert-CanvasEvidenceFileRows -Actual @($Actual.VenworksCoreSources) -Expected @($Expected.VenworksCoreSources) -Description 'Papyrus Core source evidence'
  Assert-CanvasEvidenceFileRows -Actual @($Actual.ImplementationFiles) -Expected @($Expected.ImplementationFiles) -Description 'Papyrus first-party implementation evidence'
}

function Get-CanvasExpectedCompileSources {
  param([Parameter(Mandatory = $true)][object[]]$Variants)

  $sourceVariants = @{}
  foreach ($variant in @($Variants)) {
    foreach ($relativeSource in @($variant.PapyrusScripts)) {
      $canonicalSource = ([string]$relativeSource).Replace('\', '/')
      if (!$sourceVariants.ContainsKey($canonicalSource)) {
        $sourceVariants[$canonicalSource] = [System.Collections.Generic.List[string]]::new()
      }
      $sourceVariants[$canonicalSource].Add([string]$variant.VariantKey)
    }
  }
  return $sourceVariants
}

function Assert-CanvasCompileRow {
  param(
    [Parameter(Mandatory = $true)][object]$Row,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string[]]$ExpectedVariantKeys
  )

  $source = ([string]$Row.Source).Replace('\', '/')
  $expectedOutput = [System.IO.Path]::ChangeExtension($source, '.pex').Replace('\', '/')
  Assert-CanvasExactNames -Actual @($Row.VariantKeys) -Expected @($ExpectedVariantKeys) -Description "Compile evidence variant ownership for '$source'"
  if ([string]$Row.Output -cne $expectedOutput) {
    throw "Compile evidence output identity differs for '$source'."
  }
  $sourcePath = Resolve-CanvasRequiredFile -Path (Join-Path $RepositoryRoot ('Papyrus\' + $source.Replace('/', '\'))) -Description "Papyrus source '$source'"
  $outputPath = Resolve-CanvasRequiredFile -Path (Join-Path $OutputDirectory $expectedOutput.Replace('/', '\')) -Description "Papyrus output '$expectedOutput'"
  if ([string]$Row.SourceSha256 -cne (Get-CanvasFileSha256 -Path $sourcePath) -or
      [string]$Row.Sha256 -cne (Get-CanvasFileSha256 -Path $outputPath)) {
    throw "Papyrus compile evidence is stale for '$source'."
  }
}

function Assert-CanvasCompileEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][object[]]$Variants,
    [Parameter(Mandatory = $true)][object]$Toolchain,
    [switch]$ValidateAllRows
  )

  if ([string]$Evidence.Schema -cne 'VWCANVAS_SCRIPTS/2') {
    throw 'Papyrus compile evidence uses an unexpected schema.'
  }
  Assert-CanvasCompileToolchainEvidence -Actual $Evidence.Toolchain -Expected $Toolchain
  $expectedSources = Get-CanvasExpectedCompileSources -Variants $Variants
  $allRows = @($Evidence.Scripts)
  Assert-CanvasExactNames -Actual @($allRows | ForEach-Object { [string]$_.Source }) -Expected @($allRows | ForEach-Object { [string]$_.Source } | Select-Object -Unique) -Description 'Papyrus compile evidence source identity inventory'
  foreach ($expectedSource in @($expectedSources.Keys)) {
    $matchingRows = @($allRows | Where-Object { ([string]$_.Source).Replace('\', '/') -ceq $expectedSource })
    if ($matchingRows.Count -ne 1) {
      throw "Papyrus compile evidence does not contain exactly one current row for '$expectedSource'."
    }
    Assert-CanvasCompileRow -Row $matchingRows[0] -RepositoryRoot $RepositoryRoot -OutputDirectory $OutputDirectory -ExpectedVariantKeys @($expectedSources[$expectedSource])
  }
  if ($ValidateAllRows) {
    $allVariants = @(Get-ModuleVariants)
    $allSources = Get-CanvasExpectedCompileSources -Variants $allVariants
    foreach ($row in $allRows) {
      $source = ([string]$row.Source).Replace('\', '/')
      if (!$allSources.ContainsKey($source)) {
        throw "Papyrus compile evidence contains unknown source '$source'."
      }
      Assert-CanvasCompileRow -Row $row -RepositoryRoot $RepositoryRoot -OutputDirectory $OutputDirectory -ExpectedVariantKeys @($allSources[$source])
    }
  }
}

function Get-CanvasValidRetainedCompileRows {
  param(
    [object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string[]]$SelectedSources,
    [Parameter(Mandatory = $true)][object]$Toolchain
  )

  if ($null -eq $Evidence -or [string]$Evidence.Schema -cne 'VWCANVAS_SCRIPTS/2') {
    return @()
  }
  try {
    Assert-CanvasCompileToolchainEvidence -Actual $Evidence.Toolchain -Expected $Toolchain
  }
  catch {
    Write-Warning "Retained Papyrus compile evidence was omitted because its toolchain is stale: $($_.Exception.Message)"
    return @()
  }
  $allSources = Get-CanvasExpectedCompileSources -Variants @(Get-ModuleVariants)
  $retained = [System.Collections.Generic.List[object]]::new()
  foreach ($row in @($Evidence.Scripts)) {
    $source = ([string]$row.Source).Replace('\', '/')
    if ($source -in $SelectedSources) { continue }
    try {
      if (!$allSources.ContainsKey($source)) { throw "Unknown source '$source'." }
      Assert-CanvasCompileRow -Row $row -RepositoryRoot $RepositoryRoot -OutputDirectory $OutputDirectory -ExpectedVariantKeys @($allSources[$source])
      $retained.Add($row)
    }
    catch {
      Write-Warning "Retained Papyrus compile evidence row '$source' was omitted as stale: $($_.Exception.Message)"
    }
  }
  return @($retained)
}

function Get-CanvasScaleformToolchainEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$FlexSdkPath,
    [Parameter(Mandatory = $true)][hashtable]$Matrix
  )

  $frameworks = Resolve-CanvasRequiredDirectory -Path (Join-Path $FlexSdkPath 'frameworks') -Description 'Flex frameworks directory'
  $playerGlobals = @(Get-ChildItem -LiteralPath $frameworks -Recurse -File -Filter 'playerglobal.swc')
  if ($playerGlobals.Count -ne 1) {
    throw "Expected exactly one playerglobal.swc; found $($playerGlobals.Count)."
  }
  $rows = [System.Collections.Generic.List[object]]::new()
  $rows.Add((Get-CanvasEvidenceFileRow -Key 'Java' -Path $JavaPath -DisplayPath (Split-Path -Leaf $JavaPath)))
  $rows.Add((Get-CanvasEvidenceFileRow -Key 'Jpexs' -Path $JpexsJarPath -DisplayPath (Split-Path -Leaf $JpexsJarPath)))
  $rows.Add((Get-CanvasEvidenceFileRow -Key 'FlexMxmlc' -Path (Join-Path $FlexSdkPath 'lib\mxmlc.jar') -DisplayPath 'lib/mxmlc.jar'))
  $rows.Add((Get-CanvasEvidenceFileRow -Key 'FlexConfig' -Path (Join-Path $frameworks 'flex-config.xml') -DisplayPath 'frameworks/flex-config.xml'))
  $rows.Add((Get-CanvasEvidenceFileRow -Key 'PlayerGlobal' -Path $playerGlobals[0].FullName -DisplayPath ([System.IO.Path]::GetRelativePath($FlexSdkPath, $playerGlobals[0].FullName))))
  foreach ($relativePath in @($Matrix.VwHudFixture.RequiredToolchainFiles)) {
    $rows.Add((Get-CanvasEvidenceFileRow -Key "VwHud/$relativePath" -Path (Join-Path $VwHudRepositoryPath $relativePath) -DisplayPath $relativePath))
  }
  return [ordered]@{
    VwHudRevision = [string]$Matrix.VwHudFixture.Revision
    Files = @($rows)
    ImplementationFiles = @(Get-CanvasBuildImplementationEvidence -RepositoryRoot $RepositoryRoot -Pipeline Scaleform)
  }
}

function Assert-CanvasScaleformToolchainEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Actual,
    [Parameter(Mandatory = $true)][object]$Expected
  )

  if ([string]$Actual.VwHudRevision -cne [string]$Expected.VwHudRevision) {
    throw 'Scaleform evidence uses a different VWHUD revision.'
  }
  Assert-CanvasEvidenceFileRows -Actual @($Actual.Files) -Expected @($Expected.Files) -Description 'Scaleform toolchain evidence'
  Assert-CanvasEvidenceFileRows -Actual @($Actual.ImplementationFiles) -Expected @($Expected.ImplementationFiles) -Description 'Scaleform first-party implementation evidence'
}

function Assert-CanvasMovieEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$MoviesDirectory,
    [Parameter(Mandatory = $true)][object[]]$Variants,
    [Parameter(Mandatory = $true)][object]$Toolchain,
    [switch]$ValidateAllRows
  )

  if ([string]$Evidence.Schema -cne 'VWCANVAS_SCALEFORM_MOVIES/2') {
    throw 'Canvas movie evidence uses an unexpected schema.'
  }
  Assert-CanvasScaleformToolchainEvidence -Actual $Evidence.Toolchain -Expected $Toolchain
  $rows = @($Evidence.Movies)
  Assert-CanvasExactNames -Actual @($rows.VariantKey) -Expected @($rows.VariantKey | Select-Object -Unique) -Description 'Canvas movie evidence variant inventory'
  $rowsToValidate = if ($ValidateAllRows) { $rows } else { @($rows | Where-Object { [string]$_.VariantKey -in @($Variants.VariantKey) }) }
  foreach ($variant in @($Variants)) {
    $matchingRows = @($rows | Where-Object { [string]$_.VariantKey -ceq [string]$variant.VariantKey })
    if ($matchingRows.Count -ne 1) { throw "Canvas movie evidence does not contain exactly one '$($variant.VariantKey)' row." }
  }
  foreach ($row in $rowsToValidate) {
    $variant = @(Get-ModuleVariants -VariantKeys ([string]$row.VariantKey))
    if ($variant.Count -ne 1 -or [string]$row.OutputFile -cne [string]$variant[0].ScaleformOutput) {
      throw "Canvas movie evidence has a noncanonical output identity for '$($row.VariantKey)'."
    }
    $manifest = Resolve-CanvasRequiredFile -Path (Join-Path $RepositoryRoot ('Scaleform\canvas\' + ([string]$row.Manifest).Replace('/', '\'))) -Description "Canvas manifest '$($row.Manifest)'"
    $definition = Get-CanvasBuildDefinition -ManifestPath $manifest
    $sourceRelative = [System.IO.Path]::GetRelativePath((Join-Path $RepositoryRoot 'Scaleform\canvas'), $definition.SourcePath).Replace('\', '/')
    $output = Resolve-CanvasRequiredFile -Path (Join-Path $MoviesDirectory ([string]$row.OutputFile)) -Description "Canvas movie '$($row.OutputFile)'"
    if ([string]$row.Source -cne $sourceRelative -or
        [string]$row.ManifestSha256 -cne (Get-CanvasFileSha256 -Path $manifest) -or
        [string]$row.SourceSha256 -cne (Get-CanvasFileSha256 -Path $definition.SourcePath) -or
        [string]$row.Sha256 -cne (Get-CanvasFileSha256 -Path $output) -or
        [int]$row.BuildPasses -ne 2 -or @($row.ClassInventory).Count -eq 0) {
      throw "Canvas movie evidence is stale or incomplete for '$($row.VariantKey)'."
    }
  }
}

function Get-CanvasValidRetainedMovieRows {
  param(
    [object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$MoviesDirectory,
    [Parameter(Mandatory = $true)][string[]]$SelectedVariantKeys,
    [Parameter(Mandatory = $true)][object]$Toolchain
  )

  if ($null -eq $Evidence -or [string]$Evidence.Schema -cne 'VWCANVAS_SCALEFORM_MOVIES/2') { return @() }
  try { Assert-CanvasScaleformToolchainEvidence -Actual $Evidence.Toolchain -Expected $Toolchain }
  catch {
    Write-Warning "Retained Canvas movie evidence was omitted because its toolchain is stale: $($_.Exception.Message)"
    return @()
  }
  $retained = [System.Collections.Generic.List[object]]::new()
  foreach ($row in @($Evidence.Movies)) {
    if ([string]$row.VariantKey -in $SelectedVariantKeys) { continue }
    try {
      $variant = @(Get-ModuleVariants -VariantKeys ([string]$row.VariantKey))
      Assert-CanvasMovieEvidence -Evidence ([pscustomobject]@{ Schema = 'VWCANVAS_SCALEFORM_MOVIES/2'; Toolchain = $Evidence.Toolchain; Movies = @($row) }) -RepositoryRoot $RepositoryRoot -MoviesDirectory $MoviesDirectory -Variants $variant -Toolchain $Toolchain
      $retained.Add($row)
    }
    catch {
      Write-Warning "Retained Canvas movie evidence row '$($row.VariantKey)' was omitted as stale: $($_.Exception.Message)"
    }
  }
  return @($retained)
}

function Assert-CanvasPlayerHudEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
    [Parameter(Mandatory = $true)][string]$PlayerDirectory,
    [Parameter(Mandatory = $true)][hashtable]$Matrix
  )

  if ([string]$Evidence.Schema -cne 'VWCANVAS_PLAYER_HUD_BUILD/2' -or
      $Evidence.PinnedOutputs -ne $true -or
      [string]$Evidence.VwHudRevision -cne [string]$Matrix.VwHudFixture.Revision) {
    throw 'Player HUD evidence is not a pinned VWHUD build.'
  }
  $definitionPath = Resolve-CanvasRequiredFile -Path (Join-Path $RepositoryRoot 'Scaleform\canvas\build\player-hud-watch.build.psd1') -Description 'Player HUD definition'
  $definition = Import-PowerShellDataFile -LiteralPath $definitionPath
  $patchPath = Resolve-CanvasRequiredFile -Path ([System.IO.Path]::GetFullPath((Join-Path (Split-Path $definitionPath -Parent) ([string]$definition.Patch)))) -Description 'Player HUD patch'
  $compilerPath = Resolve-CanvasRequiredFile -Path (Join-Path $VwHudRepositoryPath 'Tools\compileScaleform.ps1') -Description 'VWHUD Scaleform compiler'
  $expectedInputs = @(
    (Get-CanvasEvidenceFileRow -Key 'Definition' -Path $definitionPath -DisplayPath 'Scaleform/canvas/build/player-hud-watch.build.psd1'),
    (Get-CanvasEvidenceFileRow -Key 'Patch' -Path $patchPath -DisplayPath ([System.IO.Path]::GetRelativePath($RepositoryRoot, $patchPath))),
    (Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $compilerPath -DisplayPath 'Tools/compileScaleform.ps1')
  )
  Assert-CanvasEvidenceFileRows -Actual @($Evidence.Inputs) -Expected $expectedInputs -Description 'Player HUD build input evidence'

  $expectedComponentNames = @('playerhudcomponents.swf', 'playerhudcomponents.gfx', 'playerhudcomponents_lrg.swf', 'playerhudcomponents_lrg.gfx')
  Assert-CanvasExactNames -Actual @($definition.Movies.File) -Expected $expectedComponentNames -Description 'Player HUD definition movie inventory'
  $hostRows = @(Get-VwHudHostMovieEvidence -VwHudRepositoryPath $VwHudRepositoryPath -Matrix $Matrix)
  $expectedHostNames = @($hostRows | ForEach-Object { Split-Path -Leaf ([string]$_.Target) })
  $expectedNames = @($expectedComponentNames + $expectedHostNames)
  Assert-CanvasExactNames -Actual @($Evidence.Movies.File) -Expected $expectedNames -Description 'Player HUD evidence movie inventory'
  Assert-CanvasExactNames -Actual @(Get-ChildItem -LiteralPath $PlayerDirectory -File | ForEach-Object { $_.Name }) -Expected @($expectedNames + 'build-evidence.json') -Description 'Player HUD output inventory'
  foreach ($movie in @($definition.Movies)) {
    $row = @($Evidence.Movies | Where-Object { [string]$_.File -ceq [string]$movie.File })
    $outputPath = Resolve-CanvasRequiredFile -Path (Join-Path $PlayerDirectory ([string]$movie.File)) -Description "Player HUD movie '$($movie.File)'"
    if ($row.Count -ne 1 -or [string]$row[0].Role -cne 'WatchPresentationDisabled' -or
        [string]$row[0].VanillaSha256 -cne [string]$movie.VanillaSha256 -or
        [string]$row[0].ExpectedSha256 -cne [string]$movie.OutputSha256 -or
        [string]$row[0].Sha256 -cne [string]$movie.OutputSha256 -or
        [string]$row[0].Sha256 -cne (Get-CanvasFileSha256 -Path $outputPath)) {
      throw "Player HUD evidence is stale for '$($movie.File)'."
    }
  }
  foreach ($hostRow in $hostRows) {
    $name = Split-Path -Leaf ([string]$hostRow.Target)
    $row = @($Evidence.Movies | Where-Object { [string]$_.File -ceq $name })
    $outputPath = Resolve-CanvasRequiredFile -Path (Join-Path $PlayerDirectory $name) -Description "Player HUD host movie '$name'"
    if ($row.Count -ne 1 -or [string]$row[0].Role -cne 'PlayerHudHost' -or
        [string]$row[0].Source -cne [string]$hostRow.Source -or
        [string]$row[0].SourceSha256 -cne [string]$hostRow.Sha256 -or
        [string]$row[0].Sha256 -cne [string]$hostRow.Sha256 -or
        [string]$row[0].Sha256 -cne (Get-CanvasFileSha256 -Path $outputPath)) {
      throw "Player HUD host evidence is stale for '$name'."
    }
  }
}

function Get-CanvasPinnedHashFromFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  $line = [System.IO.File]::ReadAllText((Resolve-CanvasRequiredFile -Path $Path -Description 'Pinned hash file')).Trim()
  $match = [regex]::Match($line, '^(?<hash>[0-9A-Fa-f]{64})(?:\s{2,}.+)?$')
  if (!$match.Success) { throw "Invalid pinned hash file: $Path" }
  return $match.Groups['hash'].Value.ToUpperInvariant()
}

function Assert-CanvasShipHudEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$VwHudRepositoryPath,
    [Parameter(Mandatory = $true)][string]$ShipDirectory,
    [Parameter(Mandatory = $true)][hashtable]$Matrix
  )

  if ([string]$Evidence.Schema -cne 'VWCANVAS_SHIP_HUD_BUILD/2' -or
      $Evidence.PinnedOutputs -ne $true -or
      [string]$Evidence.VwHudRevision -cne [string]$Matrix.VwHudFixture.Revision) {
    throw 'Ship HUD evidence is not a pinned VWHUD build.'
  }
  $canvasRoot = Join-Path $RepositoryRoot 'Scaleform\canvas'
  $manifestNames = @('spaceshiphudmenu.build.xml', 'spaceshiphudmenu-lrg.build.xml')
  $trackedInputs = [System.Collections.Generic.List[object]]::new()
  foreach ($manifestName in $manifestNames) {
    $manifestPath = Join-Path $canvasRoot "build\$manifestName"
    $trackedInputs.Add((Get-CanvasEvidenceFileRow -Key "Manifest/$manifestName" -Path $manifestPath -DisplayPath "Scaleform/canvas/build/$manifestName"))
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    foreach ($attribute in @('vanillaHashFile', 'expectedHashFile')) {
      $hashName = [string]$manifest.scaleformBuild.$attribute
      $trackedInputs.Add((Get-CanvasEvidenceFileRow -Key "Hash/$hashName" -Path (Join-Path (Split-Path $manifestPath -Parent) $hashName) -DisplayPath "Scaleform/canvas/build/$hashName"))
    }
  }
  $patchPath = Join-Path $canvasRoot 'patches\spaceship-hud-auxiliary-loader.xml'
  $trackedInputs.Add((Get-CanvasEvidenceFileRow -Key 'Patch' -Path $patchPath -DisplayPath 'Scaleform/canvas/patches/spaceship-hud-auxiliary-loader.xml'))
  $compilerPath = Join-Path $VwHudRepositoryPath ([string]$Matrix.VwHudFixture.ShipCompilerFile)
  $trackedInputs.Add((Get-CanvasEvidenceFileRow -Key 'Compiler' -Path $compilerPath -DisplayPath ([string]$Matrix.VwHudFixture.ShipCompilerFile)))
  Assert-CanvasEvidenceFileRows -Actual @($Evidence.Inputs) -Expected @($trackedInputs) -Description 'Ship HUD build input evidence'

  $expectedMovies = @('spaceshiphudmenu.swf', 'spaceshiphudmenu_lrg.swf')
  Assert-CanvasExactNames -Actual @($Evidence.Movies.File) -Expected $expectedMovies -Description 'Ship HUD evidence movie inventory'
  Assert-CanvasExactNames -Actual @(Get-ChildItem -LiteralPath $ShipDirectory -File | ForEach-Object { $_.Name }) -Expected @($expectedMovies + 'build-evidence.json') -Description 'Ship HUD output inventory'
  foreach ($manifestName in $manifestNames) {
    $manifestPath = Join-Path $canvasRoot "build\$manifestName"
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    $name = [string]$manifest.scaleformBuild.outputFile
    $row = @($Evidence.Movies | Where-Object { [string]$_.File -ceq $name })
    $vanillaSha = Get-CanvasPinnedHashFromFile -Path (Join-Path (Split-Path $manifestPath -Parent) ([string]$manifest.scaleformBuild.vanillaHashFile))
    $expectedSha = Get-CanvasPinnedHashFromFile -Path (Join-Path (Split-Path $manifestPath -Parent) ([string]$manifest.scaleformBuild.expectedHashFile))
    $output = Resolve-CanvasRequiredFile -Path (Join-Path $ShipDirectory $name) -Description "Ship HUD movie '$name'"
    if ($row.Count -ne 1 -or [string]$row[0].Manifest -cne "Scaleform/canvas/build/$manifestName" -or
        [string]$row[0].VanillaSha256 -cne $vanillaSha -or [string]$row[0].ExpectedSha256 -cne $expectedSha -or
        [string]$row[0].Sha256 -cne $expectedSha -or [string]$row[0].Sha256 -cne (Get-CanvasFileSha256 -Path $output)) {
      throw "Ship HUD evidence is stale for '$name'."
    }
  }
}

function Assert-CanvasScaleformAggregateEvidence {
  param(
    [Parameter(Mandatory = $true)][object]$Evidence,
    [Parameter(Mandatory = $true)][string]$ScaleformDirectory,
    [Parameter(Mandatory = $true)][string[]]$RequiredVariantKeys,
    [bool]$RequirePlayerHud,
    [bool]$RequireShipHud
  )

  if ([string]$Evidence.Schema -cne 'VWCANVAS_SCALEFORM_BUILD/2') {
    throw 'Scaleform aggregate evidence uses an unexpected schema.'
  }
  foreach ($key in $RequiredVariantKeys) {
    if ([string]$key -cnotin @($Evidence.Variants)) { throw "Scaleform aggregate evidence omits '$key'." }
  }
  $moviesEvidencePath = Resolve-CanvasRequiredFile -Path (Join-Path $ScaleformDirectory 'movies\build-evidence.json') -Description 'Canvas movie evidence'
  if ([string]$Evidence.CanvasMoviesEvidenceSha256 -cne (Get-CanvasFileSha256 -Path $moviesEvidencePath)) {
    throw 'Scaleform aggregate evidence does not bind the current Canvas movie evidence.'
  }
  if ($RequirePlayerHud) {
    $path = Resolve-CanvasRequiredFile -Path (Join-Path $ScaleformDirectory 'player-hud\build-evidence.json') -Description 'Player HUD evidence'
    if ([string]$Evidence.PlayerHudEvidenceSha256 -cne (Get-CanvasFileSha256 -Path $path)) { throw 'Scaleform aggregate evidence does not bind the Player HUD evidence.' }
  }
  if ($RequireShipHud) {
    $path = Resolve-CanvasRequiredFile -Path (Join-Path $ScaleformDirectory 'ship-hud\build-evidence.json') -Description 'Ship HUD evidence'
    if ([string]$Evidence.ShipHudEvidenceSha256 -cne (Get-CanvasFileSha256 -Path $path)) { throw 'Scaleform aggregate evidence does not bind the Ship HUD evidence.' }
  }
}
