$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-CanvasSourceTokens {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RequiredTokens,
    [Parameter(Mandatory = $true)][string]$Description
  )

  foreach ($token in @($RequiredTokens)) {
    if (!$Source.Contains($token)) {
      throw "$Description is missing required token '$token'."
    }
  }
}

function Get-CanvasActionScriptPatch {
  param([Parameter(Mandatory = $true)][string]$PatchPath)

  $resolvedPatchPath = Resolve-CanvasRequiredFile -Path $PatchPath -Description 'Canvas ActionScript patch'
  [xml]$document = Get-Content -LiteralPath $resolvedPatchPath -Raw
  $patch = $document.actionScriptPatch
  if ($null -eq $patch) {
    throw "Invalid Canvas ActionScript patch: $resolvedPatchPath"
  }
  $insertions = @($patch.SelectNodes('insertions/insertion'))
  if (
      [string]::IsNullOrWhiteSpace([string]$patch.script) -or
      $insertions.Count -eq 0) {
    throw "Invalid Canvas ActionScript patch: $resolvedPatchPath"
  }
  return [pscustomobject]@{
    Path = $resolvedPatchPath
    Script = [string]$patch.script
    Insertions = $insertions
    RequiredSourceTokens = @($patch.SelectNodes('validation/requiredSourceTokens/token') | ForEach-Object { [string]$_.InnerText })
    RequiredInspectionTokens = @($patch.SelectNodes('validation/requiredInspectionTokens/token') | ForEach-Object { [string]$_.InnerText })
  }
}

function Get-CanvasOrdinalOccurrenceCount {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $count = 0
  $offset = 0
  while ($offset -le $Source.Length - $Value.Length) {
    $index = $Source.IndexOf($Value, $offset, [System.StringComparison]::Ordinal)
    if ($index -lt 0) { break }
    $count++
    $offset = $index + $Value.Length
  }
  return $count
}

function Apply-ActionScriptPatch {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch
  )

  $resolvedSourcePath = Resolve-CanvasRequiredFile -Path $SourcePath -Description "Exported ActionScript '$($Patch.Script)'"
  $source = [System.IO.File]::ReadAllText($resolvedSourcePath)
  foreach ($insertion in @($Patch.Insertions)) {
    $position = [string]$insertion.position
    $anchor = [string]$insertion.anchor.InnerText
    $content = [string]$insertion.content.InnerText
    if ($position -cnotin @('before', 'after') -or [string]::IsNullOrEmpty($anchor)) {
      throw "Canvas ActionScript patch '$($Patch.Path)' contains an invalid insertion."
    }
    $anchorCount = Get-CanvasOrdinalOccurrenceCount -Source $source -Value $anchor
    if ($anchorCount -ne 1) {
      throw "Canvas ActionScript patch '$($Patch.Path)' expected one '$($Patch.Script)' anchor but found $anchorCount."
    }
    $anchorIndex = $source.IndexOf($anchor, [System.StringComparison]::Ordinal)
    $insertionIndex = if ($position -ceq 'before') { $anchorIndex } else { $anchorIndex + $anchor.Length }
    $source = $source.Insert($insertionIndex, $content)
  }
  Assert-CanvasSourceTokens -Source $source -RequiredTokens @($Patch.RequiredSourceTokens) -Description "Patched ActionScript '$($Patch.Script)'"
  Write-CanvasUtf8WithoutBom -Path $resolvedSourcePath -Text $source
}

function Find-CanvasExportedActionScript {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptsDirectory,
    [Parameter(Mandatory = $true)][string]$ScriptName
  )

  $scriptMatches = @(Get-ChildItem -LiteralPath $ScriptsDirectory -Recurse -File -Filter '*.as' | Where-Object { $_.BaseName -ceq $ScriptName })
  if ($scriptMatches.Count -ne 1) {
    throw "Expected exactly one exported ActionScript file for '$ScriptName'; found $($scriptMatches.Count)."
  }
  return $scriptMatches[0].FullName
}

function Get-CanvasPlayerHudBuildDefinition {
  param([Parameter(Mandatory = $true)][string]$DefinitionPath)

  $resolvedDefinitionPath = Resolve-CanvasRequiredFile -Path $DefinitionPath -Description 'Player HUD Watch build definition'
  $definition = Import-PowerShellDataFile -LiteralPath $resolvedDefinitionPath
  $movies = @($definition.Movies | ForEach-Object { [string]$_ })
  if ([string]$definition.Schema -cne 'VWCANVAS_WATCH_BUILD/1' -or
      [string]::IsNullOrWhiteSpace([string]$definition.Patch) -or
      $movies.Count -eq 0 -or
      @($movies | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw "Invalid Player HUD Watch build definition: $resolvedDefinitionPath"
  }
  return [pscustomobject]@{
    Movies = $movies
    PatchPath = Resolve-CanvasRequiredFile -Path ([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedDefinitionPath) ([string]$definition.Patch)))) -Description 'Player HUD Watch patch'
  }
}

function Get-CanvasPatchedMovieBuildDefinition {
  param([Parameter(Mandatory = $true)][string]$ManifestPath)

  $resolvedManifestPath = Resolve-CanvasRequiredFile -Path $ManifestPath -Description 'Canvas patched movie manifest'
  [xml]$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw
  $build = $manifest.scaleformBuild
  if ($null -eq $build) {
    throw "Invalid Canvas patched movie manifest: $resolvedManifestPath"
  }
  $patches = @($build.SelectNodes('actionScriptPatches/patch'))
  if (
      [string]::IsNullOrWhiteSpace([string]$build.inputFile) -or
      [string]::IsNullOrWhiteSpace([string]$build.outputFile) -or
      $patches.Count -ne 1 -or
      [string]::IsNullOrWhiteSpace([string]$patches[0].path)) {
    throw "Invalid Canvas patched movie manifest: $resolvedManifestPath"
  }
  return [pscustomobject]@{
    InputFile = [string]$build.inputFile
    OutputFile = [string]$build.outputFile
    PatchPath = Resolve-CanvasRequiredFile -Path ([System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $resolvedManifestPath) ([string]$patches[0].path)))) -Description 'Canvas patched movie patch'
  }
}

function Invoke-CanvasPatchedMovieBuild {
  param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$PatchPath,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$FlexSdkPath,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [switch]$KeepWork
  )

  $resolvedInputPath = Assert-CanvasScaleformFile -Path $InputPath -Description 'Installed Scaleform patch input'
  $resolvedJavaPath = Resolve-CanvasRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-CanvasRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-CanvasRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  $patch = Get-CanvasActionScriptPatch -PatchPath $PatchPath
  $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
  New-Item -ItemType Directory -Force -Path $resolvedWorkDirectory | Out-Null
  $buildWorkDirectory = Join-Path $resolvedWorkDirectory ([guid]::NewGuid().ToString('N'))
  $exportDirectory = Join-Path $buildWorkDirectory 'exported'
  $inspectionDirectory = Join-Path $buildWorkDirectory 'inspection'
  New-Item -ItemType Directory -Path $exportDirectory, $inspectionDirectory | Out-Null
  try {
    Invoke-CanvasJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-format', 'script:as', '-selectclass', $patch.Script, '-onerror', 'abort', '-export', 'script', $exportDirectory, $resolvedInputPath) -Description "JPEXS $($patch.Script) ActionScript export"
    $sourcePath = Find-CanvasExportedActionScript -ScriptsDirectory $exportDirectory -ScriptName $patch.Script
    Apply-ActionScriptPatch -SourcePath $sourcePath -Patch $patch
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputPath) | Out-Null
    Invoke-CanvasJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-config', "flexSdkLocation=$resolvedFlexSdkPath", '-onerror', 'abort', '-importScript', $resolvedInputPath, $resolvedOutputPath, $exportDirectory) -Description "JPEXS $($patch.Script) ActionScript import"
    [void](Assert-CanvasScaleformFile -Path $resolvedOutputPath -Description "Patched $($patch.Script) Scaleform movie")
    Invoke-CanvasJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-format', 'script:as', '-onerror', 'abort', '-export', 'script', $inspectionDirectory, $resolvedOutputPath) -Description "JPEXS patched $($patch.Script) inspection export"
    $inspectionPath = Find-CanvasExportedActionScript -ScriptsDirectory $inspectionDirectory -ScriptName $patch.Script
    Assert-CanvasSourceTokens -Source ([System.IO.File]::ReadAllText($inspectionPath)) -RequiredTokens @($patch.RequiredInspectionTokens) -Description "Patched $($patch.Script) inspection"
    return $resolvedOutputPath
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Canvas patch files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-CanvasRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}

function Assert-CanvasScaleformOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedDirectory = Resolve-CanvasRequiredDirectory -Path $Directory -Description $Description
  $items = @(Get-ChildItem -LiteralPath $resolvedDirectory -Force)
  if (@($items | Where-Object { $_.PSIsContainer }).Count -ne 0) {
    throw "$Description contains unexpected directories."
  }
  Assert-CanvasExactNames -Actual @($items.Name) -Expected $ExpectedFiles -Description "$Description file inventory"
  foreach ($fileName in $ExpectedFiles) {
    [void](Assert-CanvasScaleformFile -Path (Join-Path $resolvedDirectory $fileName) -Description "$Description '$fileName'")
  }
}

function Publish-CanvasScaleformFile {
  param(
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedCandidate = Assert-CanvasScaleformFile -Path $CandidatePath -Description 'Canvas Scaleform file candidate'
  $resolvedDestination = [System.IO.Path]::GetFullPath($DestinationPath)
  Assert-CanvasRemovalPath -Path $resolvedDestination -AllowedRoot $AllowedRoot
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDestination) | Out-Null
  $expectedHash = Get-CanvasFileSha256 -Path $resolvedCandidate
  $temporaryPath = "$resolvedDestination.$PID-$([guid]::NewGuid().ToString('N')).new"
  try {
    Copy-Item -LiteralPath $resolvedCandidate -Destination $temporaryPath
    if ((Get-CanvasFileSha256 -Path $temporaryPath) -cne $expectedHash) {
      throw "Canvas Scaleform publication copy differs for '$resolvedDestination'."
    }
    [System.IO.File]::Move($temporaryPath, $resolvedDestination, $true)
    [void](Assert-CanvasScaleformFile -Path $resolvedDestination -Description 'Published Canvas Scaleform file')
  }
  finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
  }
}

function Invoke-CanvasHudDirectoryMove {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  Move-Item -LiteralPath $Source -Destination $Destination
}

function Invoke-CanvasHudDirectoryRemoval {
  param([Parameter(Mandatory = $true)][string]$Path)

  Remove-Item -LiteralPath $Path -Recurse -Force
}

function Publish-CanvasHudOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$CandidateDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedCandidate = Resolve-CanvasRequiredDirectory -Path $CandidateDirectory -Description 'Selected HUD output candidate'
  $resolvedDestination = [System.IO.Path]::GetFullPath($DestinationDirectory)
  $resolvedWorkDirectory = Resolve-CanvasRequiredDirectory -Path $WorkDirectory -Description 'Selected HUD publication work directory'
  Assert-CanvasRemovalPath -Path $resolvedCandidate -AllowedRoot $AllowedRoot
  Assert-CanvasRemovalPath -Path $resolvedDestination -AllowedRoot $AllowedRoot
  Assert-CanvasRemovalPath -Path $resolvedWorkDirectory -AllowedRoot $AllowedRoot
  if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
    throw "Selected HUD output destination is a file: $resolvedDestination"
  }
  $backupPath = Join-Path $resolvedWorkDirectory ('hud-publication-backup-' + [guid]::NewGuid().ToString('N'))
  Assert-CanvasRemovalPath -Path $backupPath -AllowedRoot $AllowedRoot
  if (Test-Path -LiteralPath $backupPath) {
    throw "Refusing to replace preexisting HUD publication recovery material: $backupPath"
  }

  $existingOutputMoved = $false
  try {
    if (Test-Path -LiteralPath $resolvedDestination -PathType Container) {
      Invoke-CanvasHudDirectoryMove -Source $resolvedDestination -Destination $backupPath
      $existingOutputMoved = $true
    }
    Invoke-CanvasHudDirectoryMove -Source $resolvedCandidate -Destination $resolvedDestination
  }
  catch {
    $publicationError = $_
    if ($existingOutputMoved -and !(Test-Path -LiteralPath $resolvedDestination) -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
      try { Invoke-CanvasHudDirectoryMove -Source $backupPath -Destination $resolvedDestination }
      catch {
        throw "Selected HUD publication failed and its prior output could not be restored. Recovery remains at '$backupPath'. Publication error: $($publicationError.Exception.Message) Recovery error: $($_.Exception.Message)"
      }
    }
    throw $publicationError
  }
  if ($existingOutputMoved) { Invoke-CanvasHudDirectoryRemoval -Path $backupPath }
}

function Publish-CanvasValidatedHudOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$CandidateDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-CanvasScaleformOutputSet -Directory $CandidateDirectory -ExpectedFiles $ExpectedFiles -Description "$Description candidate"
  Publish-CanvasHudOutputSet -CandidateDirectory $CandidateDirectory -DestinationDirectory $DestinationDirectory -WorkDirectory $WorkDirectory -AllowedRoot $AllowedRoot
  Assert-CanvasScaleformOutputSet -Directory $DestinationDirectory -ExpectedFiles $ExpectedFiles -Description "Published $Description output"
}
