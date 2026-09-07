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

function Resolve-CanvasRequiredFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $resolved -or !(Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
    throw "$Description does not exist: $Path"
  }
  return $resolved.Path
}

function Assert-CanvasPapyrusFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = Resolve-CanvasRequiredFile -Path $Path -Description $Description
  $header = [byte[]]::new(16)
  $stream = [System.IO.File]::OpenRead($resolvedPath)
  try {
    if ($stream.Length -lt $header.Length -or $stream.Read($header, 0, $header.Length) -ne $header.Length) {
      throw "$Description is empty or too short to contain a Papyrus PEX header: $resolvedPath"
    }
  }
  finally {
    $stream.Dispose()
  }
  $signature = [System.BitConverter]::ToString($header, 0, 4)
  if ($signature -cne 'DE-C0-57-FA') {
    throw "$Description has an unsupported Papyrus PEX header '$signature': $resolvedPath"
  }
  return $resolvedPath
}

function Assert-CanvasScaleformFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = Resolve-CanvasRequiredFile -Path $Path -Description $Description
  $header = [byte[]]::new(8)
  $stream = [System.IO.File]::OpenRead($resolvedPath)
  try {
    if ($stream.Length -lt $header.Length -or $stream.Read($header, 0, $header.Length) -ne $header.Length) {
      throw "$Description is empty or too short to be a Scaleform movie: $resolvedPath"
    }
  }
  finally {
    $stream.Dispose()
  }
  $signature = [System.Text.Encoding]::ASCII.GetString($header, 0, 3)
  if ($signature -cnotin @('FWS', 'CWS', 'ZWS', 'GFX')) {
    throw "$Description has an unsupported Scaleform header '$signature': $resolvedPath"
  }
  return $resolvedPath
}

function Resolve-CanvasRequiredDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $resolved -or !(Test-Path -LiteralPath $resolved.Path -PathType Container)) {
    throw "$Description does not exist: $Path"
  }
  return $resolved.Path
}

function Get-CanvasNormalizedFullPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'A filesystem path cannot be empty.'
  }

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $pathRoot = [System.IO.Path]::GetPathRoot($fullPath)
  if ($fullPath.Length -gt $pathRoot.Length) {
    return $fullPath.TrimEnd(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
  }
  return $fullPath
}

function Test-CanvasOverlappingPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Left,

    [Parameter(Mandatory = $true)]
    [string]$Right
  )

  $leftPath = Get-CanvasNormalizedFullPath -Path $Left
  $rightPath = Get-CanvasNormalizedFullPath -Path $Right
  if ([string]::Equals($leftPath, $rightPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $leftPrefix = if ($leftPath.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or
      $leftPath.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)) {
    $leftPath
  }
  else {
    $leftPath + [System.IO.Path]::DirectorySeparatorChar
  }
  $rightPrefix = if ($rightPath.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or
      $rightPath.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar)) {
    $rightPath
  }
  else {
    $rightPath + [System.IO.Path]::DirectorySeparatorChar
  }

  return $leftPath.StartsWith($rightPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
    $rightPath.StartsWith($leftPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-CanvasUtf8WithoutBom {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Text
  )

  $canonicalText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $canonicalText, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-CanvasUuid {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $hex = '[0-9a-fA-F]'
  $dashed = "$hex{8}-$hex{4}-$hex{4}-$hex{4}-$hex{12}"
  $format = if ($Value -cmatch "\A$dashed\z") { 'D' }
    elseif ($Value -cmatch "\A\{$dashed\}\z") { 'B' }
    elseif ($Value -cmatch "\A$hex{32}\z") { 'N' }
    else { throw 'Invalid consumer UUID shape.' }
  $parsed = [guid]::Empty
  if (![guid]::TryParseExact($Value, $format, [ref]$parsed) -or $parsed -eq [guid]::Empty) {
    throw 'Invalid or nil consumer UUID.'
  }
  return $parsed.ToString('D').ToLowerInvariant()
}

# Reference parser for the bounded single-consumer command; this is not a Scaleform VM test.
function ConvertFrom-CanvasUiLoadPacket {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Packet)
  $prefix = 'VWC_EVT/1|canvas.ui.load|'
  if ($Packet.Length -gt 512 -or $Packet -cnotmatch '\A[\x20-\x7e]+\z' -or !$Packet.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Invalid UI load envelope.'
  }
  $cursor = $prefix.Length
  $values = @()
  foreach ($maximum in @(1, 38, 4, 180, 180)) {
    $delimiter = $Packet.IndexOf(':', $cursor)
    if ($delimiter -le $cursor -or $delimiter - $cursor -gt 6) { throw 'Invalid UI load frame.' }
    $lengthText = $Packet.Substring($cursor, $delimiter - $cursor)
    if ($lengthText -cnotmatch '\A[0-9]+\z') { throw 'Invalid UI load frame length.' }
    $length = [int]$lengthText
    $cursor = $delimiter + 1
    if ($length -gt $maximum -or $cursor + $length -gt $Packet.Length) { throw 'Truncated or oversized UI load frame.' }
    $values += $Packet.Substring($cursor, $length)
    $cursor += $length
  }
  if ($cursor -ne $Packet.Length -or $values[0] -cne '1' -or $values[2] -cnotmatch '\A[0-9]{1,4}\z' -or [int]$values[2] -lt 1) {
    throw 'Invalid UI load protocol, version or trailing data.'
  }
  $id = ConvertTo-CanvasUuid -Value $values[1]
  $normal = [regex]::Match($values[3], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/normal\.swf\z', 'IgnoreCase')
  $large = [regex]::Match($values[4], '\AVenworksCanvas/Consumers/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])/large\.swf\z', 'IgnoreCase')
  if (!$normal.Success -or !$large.Success -or $normal.Groups[1].Value.Contains('..') -or $normal.Groups[1].Value -ine $large.Groups[1].Value) {
    throw 'UI load paths must share one safe local namespace.'
  }
  $root = 'VenworksCanvas/Consumers/' + $normal.Groups[1].Value.ToLowerInvariant() + '/'
  return [pscustomobject]@{ ConsumerId = $id; Version = [int]$values[2]; NormalPath = $root + 'normal.swf'; LargePath = $root + 'large.swf' }
}

function Assert-CanvasArtifactHeader {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $header = [byte[]]::new(24)
    $read = $stream.Read($header, 0, $header.Length)
    $prefix = [Text.Encoding]::ASCII.GetString($header, 0, $read)
    if ($prefix.StartsWith('version https://git-lfs', [StringComparison]::Ordinal)) {
      throw "Artifact is a Git LFS pointer, not a deployed binary: $Path"
    }
    if ($read -ne 24) { throw "Artifact header is truncated: $Path" }
    $magic = [Text.Encoding]::ASCII.GetString($header, 0, 4)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
      '.esm' {
        $recordBytes = [BitConverter]::ToUInt32($header, 4)
        if ($magic -cne 'TES4' -or $recordBytes -lt 18 -or [long]$recordBytes + 24 -gt $stream.Length) {
          throw "Invalid or truncated ESM header: $Path"
        }
      }
      '.ba2' {
        $version = [BitConverter]::ToUInt32($header, 4)
        $archiveType = [Text.Encoding]::ASCII.GetString($header, 8, 4)
        $fileCount = [BitConverter]::ToUInt32($header, 12)
        $nameOffset = [BitConverter]::ToUInt64($header, 16)
        if ($magic -cne 'BTDX' -or $version -ne 2 -or $archiveType -cne 'GNRL' -or $fileCount -eq 0 -or
            $nameOffset -lt 32L + (36L * $fileCount) -or $nameOffset -ge [uint64]$stream.Length -or
            $nameOffset + (2L * $fileCount) -gt [uint64]$stream.Length) {
          throw "Invalid or truncated BA2 header: $Path"
        }
      }
      default { throw "Unsupported artifact extension: $Path" }
    }
  }
  finally { $stream.Dispose() }
}

function Get-CanvasFileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-CanvasRemovalPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$AllowedRoot
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
  if (!$fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove path outside the canvas work root: $fullPath"
  }
}

function Get-CanvasMatrix {
  param(
    [string]$RepositoryRoot = ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
  )

  $matrixPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $RepositoryRoot 'Scaleform\canvas\canvas-matrix.psd1') `
    -Description 'Canvas matrix'
  return Import-PowerShellDataFile -LiteralPath $matrixPath
}

function Import-CanvasEnvironment {
  param(
    [string]$Path = (Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) '.env')
  )

  $environmentPath = Resolve-CanvasRequiredFile -Path $Path -Description 'Canvas environment file'
  foreach ($line in [System.IO.File]::ReadAllLines($environmentPath)) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
      continue
    }
    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) {
      throw "Invalid environment entry in $environmentPath."
    }
    $name = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
  }
}

function Resolve-CanvasExecutable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$FileName,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $candidate = $Path
  if (Test-Path -LiteralPath $Path -PathType Container) {
    $candidate = Join-Path $Path $FileName
  }
  return Resolve-CanvasRequiredFile -Path $candidate -Description $Description
}

function Get-CanvasStagingSelection {
  <# Selects package variants from sharedConfig.ps1 without duplicating variant metadata. #>
  param([string[]]$VariantKeys)

  return @(Get-ModuleVariants -VariantKeys $VariantKeys)
}

function Invoke-CanvasJavaJar {
  param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,

    [Parameter(Mandatory = $true)]
    [string]$JarPath,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  & $JavaPath -jar $JarPath @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE."
  }
}

function Normalize-CanvasMovie {
  param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,

    [Parameter(Mandatory = $true)]
    [string]$JpexsJarPath,

    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$WorkPath
  )

  $rawXmlPath = Join-Path $WorkPath 'compiled.xml'
  $normalizedXmlPath = Join-Path $WorkPath 'normalized.xml'
  Invoke-CanvasJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-swf2xml', $InputPath, $rawXmlPath) `
    -Description 'JPEXS canvas movie XML export'

  [xml]$movie = Get-Content -LiteralPath $rawXmlPath -Raw
  $tagsNode = $movie.SelectSingleNode('/swf/tags')
  if ($null -eq $tagsNode) {
    throw 'Generated canvas movie does not contain a root tag collection.'
  }
  foreach ($tag in @($movie.SelectNodes('/swf/tags/item[@type="MetadataTag" or @type="ProductInfoTag"]'))) {
    [void]$tagsNode.RemoveChild($tag)
  }
  $fileAttributes = $movie.SelectSingleNode('/swf/tags/item[@type="FileAttributesTag"]')
  if ($null -ne $fileAttributes) {
    $fileAttributes.SetAttribute('hasMetadata', 'false')
  }

  $settings = [System.Xml.XmlWriterSettings]::new()
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $settings.Indent = $true
  $settings.NewLineChars = "`n"
  $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
  $writer = [System.Xml.XmlWriter]::Create($normalizedXmlPath, $settings)
  try {
    $movie.Save($writer)
  }
  finally {
    $writer.Dispose()
  }

  Invoke-CanvasJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-xml2swf', $normalizedXmlPath, $OutputPath) `
    -Description 'JPEXS normalized canvas movie rebuild'
}

function Get-CanvasClassInventory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptsDirectory
  )

  $definitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($scriptFile in @(Get-ChildItem -LiteralPath $ScriptsDirectory -Recurse -File -Filter '*.as')) {
    $source = [System.IO.File]::ReadAllText($scriptFile.FullName)
    $packageMatch = [regex]::Match($source, '(?m)^\s*package(?:\s+([A-Za-z_][A-Za-z0-9_.]*))?\s*$')
    $packageName = if ($packageMatch.Success) { [string]$packageMatch.Groups[1].Value } else { '' }
    foreach ($definitionMatch in [regex]::Matches(
      $source,
      '(?m)^\s*(?:(?:public|internal|final|dynamic)\s+)*(?:class|interface)\s+([A-Za-z_][A-Za-z0-9_]*)\b'
    )) {
      $definitionName = [string]$definitionMatch.Groups[1].Value
      $qualifiedName = if ([string]::IsNullOrEmpty($packageName)) {
        $definitionName
      }
      else {
        "$packageName.$definitionName"
      }
      if (!$definitions.Add($qualifiedName)) {
        throw "Canvas movie exports duplicate definition '$qualifiedName'."
      }
    }
  }

  [string[]]$inventory = @($definitions)
  [System.Array]::Sort($inventory, [System.StringComparer]::Ordinal)
  if ($inventory.Count -eq 0) {
    throw 'Canvas movie did not export any ActionScript definitions.'
  }
  return $inventory
}

function Get-CanvasBuildDefinition {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
  )

  $resolvedManifestPath = Resolve-CanvasRequiredFile `
    -Path $ManifestPath `
    -Description 'Canvas movie build manifest'
  [xml]$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw
  $build = $manifest.canvasMovieBuild
  if ($null -eq $build -or
      [string]::IsNullOrWhiteSpace([string]$build.name) -or
      [string]::IsNullOrWhiteSpace([string]$build.role) -or
      [string]::IsNullOrWhiteSpace([string]$build.outputFile) -or
      [string]::IsNullOrWhiteSpace([string]$build.documentClass) -or
      [string]::IsNullOrWhiteSpace([string]$build.className) -or
      [int]$build.stageWidth -le 0 -or
      [int]$build.stageHeight -le 0 -or
      [int]$build.frameRate -le 0) {
    throw "Invalid canvas movie build manifest: $resolvedManifestPath"
  }
  $manifestDirectory = Split-Path -Parent $resolvedManifestPath
  $requiredTokens = @($build.requiredTokens.token | ForEach-Object { [string]$_ })
  $forbiddenTokens = @($build.forbiddenTokens.token | ForEach-Object { [string]$_ })
  if ($requiredTokens.Count -eq 0 -or $forbiddenTokens.Count -eq 0) {
    throw "Canvas movie manifest must declare required and forbidden tokens: $resolvedManifestPath"
  }
  return [pscustomobject]@{
    Name = [string]$build.name
    Role = [string]$build.role
    OutputFile = [string]$build.outputFile
    ManifestPath = $resolvedManifestPath
    SourcePath = Resolve-CanvasRequiredFile `
      -Path (Join-Path $manifestDirectory ([string]$build.documentClass)) `
      -Description 'Canvas ActionScript entrypoint'
    ClassName = [string]$build.className
    StageWidth = [int]$build.stageWidth
    StageHeight = [int]$build.stageHeight
    FrameRate = [int]$build.frameRate
    RequiredTokens = $requiredTokens
    ForbiddenTokens = $forbiddenTokens
  }
}

function Invoke-CanvasCompilation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,

    [Parameter(Mandatory = $true)]
    [string]$MxmlcJarPath,

    [Parameter(Mandatory = $true)]
    [string]$FlexConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$PlayerGlobalPath,

    [Parameter(Mandatory = $true)]
    [string]$FlexFrameworksPath,

    [Parameter(Mandatory = $true)]
    [string]$EntrypointPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [int]$StageWidth,

    [Parameter(Mandatory = $true)]
    [int]$StageHeight,

    [Parameter(Mandatory = $true)]
    [int]$FrameRate
  )

  $compilerArguments = @(
    "-load-config=$FlexConfigPath",
    '-compiler.library-path=',
    "-compiler.external-library-path=$PlayerGlobalPath",
    '-compiler.source-path', $SourceRoot,
    '-compiler.debug=false',
    '-compiler.optimize=true',
    '-compiler.compress=true',
    '-compiler.omit-trace-statements=true',
    '-use-network=false',
    '-target-player=11.1.0',
    '-swf-version=12',
    '-default-size', $StageWidth, $StageHeight,
    "-default-frame-rate=$FrameRate",
    '-output', $OutputPath,
    $EntrypointPath
  )
  Push-Location $FlexFrameworksPath
  try {
    Invoke-CanvasJavaJar `
      -JavaPath $JavaPath `
      -JarPath $MxmlcJarPath `
      -Arguments $compilerArguments `
      -Description 'Apache Flex canvas compilation'
  }
  finally {
    Pop-Location
  }
}

function Assert-CanvasMovie {
  param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,

    [Parameter(Mandatory = $true)]
    [string]$JpexsJarPath,

    [Parameter(Mandatory = $true)]
    [string]$MoviePath,

    [Parameter(Mandatory = $true)]
    [string]$WorkPath,

    [Parameter(Mandatory = $true)]
    [pscustomobject]$Definition
  )

  Assert-CanvasScaleformFile -Path $MoviePath -Description "Generated $($Definition.Name) Canvas movie"

  $exportDirectory = Join-Path $WorkPath 'inspection-scripts'
  Invoke-CanvasJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-format', 'script:as', '-export', 'script', $exportDirectory, $MoviePath) `
    -Description "JPEXS $($Definition.Name) ActionScript export"
  $inventory = @(Get-CanvasClassInventory -ScriptsDirectory $exportDirectory)
  if ($inventory.Count -ne 1 -or $inventory[0] -cne $Definition.ClassName) {
    throw "Canvas movie '$($Definition.Name)' exports unexpected classes: $([string]::Join(', ', $inventory))"
  }
  $validationSource = @(Get-ChildItem -LiteralPath $exportDirectory -Recurse -File -Filter '*.as' | ForEach-Object {
    [System.IO.File]::ReadAllText($_.FullName)
  }) -join "`n"
  foreach ($requiredToken in @($Definition.RequiredTokens)) {
    if (!$validationSource.Contains([string]$requiredToken)) {
      throw "Canvas movie '$($Definition.Name)' is missing required bytecode token '$requiredToken'."
    }
  }
  foreach ($forbiddenToken in @($Definition.ForbiddenTokens)) {
    if ($validationSource.Contains([string]$forbiddenToken)) {
      throw "Canvas movie '$($Definition.Name)' contains forbidden bytecode token '$forbiddenToken'."
    }
  }
  return $inventory
}

function Invoke-CanvasMovieBuild {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$WorkDirectory,

    [Parameter(Mandatory = $true)]
    [string]$JavaPath,

    [Parameter(Mandatory = $true)]
    [string]$JpexsJarPath,

    [Parameter(Mandatory = $true)]
    [string]$FlexSdkPath,

    [switch]$KeepWork
  )

  $definition = Get-CanvasBuildDefinition -ManifestPath $ManifestPath
  $resolvedJavaPath = Resolve-CanvasRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-CanvasRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-CanvasRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  $mxmlcJarPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $resolvedFlexSdkPath 'lib\mxmlc.jar') `
    -Description 'Apache Flex mxmlc compiler'
  $flexFrameworksPath = Resolve-CanvasRequiredDirectory `
    -Path (Join-Path $resolvedFlexSdkPath 'frameworks') `
    -Description 'Apache Flex frameworks directory'
  $flexConfigPath = Resolve-CanvasRequiredFile `
    -Path (Join-Path $flexFrameworksPath 'flex-config.xml') `
    -Description 'Apache Flex compiler configuration'
  $playerGlobalMatches = @(Get-ChildItem -LiteralPath $flexFrameworksPath -Recurse -File -Filter 'playerglobal.swc')
  if ($playerGlobalMatches.Count -ne 1) {
    throw "Expected exactly one playerglobal.swc in the Apache Flex SDK; found $($playerGlobalMatches.Count)."
  }

  $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
  New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkDirectory | Out-Null
  $buildWorkDirectory = Join-Path $resolvedWorkDirectory ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $buildWorkDirectory | Out-Null
  $sourceRoot = Join-Path $buildWorkDirectory 'source'
  $compileRoot = Join-Path $buildWorkDirectory 'compile'
  New-Item -ItemType Directory -Path $sourceRoot, $compileRoot | Out-Null
  $entrypointPath = Join-Path $sourceRoot ([System.IO.Path]::GetFileName($definition.SourcePath))
  Copy-Item -LiteralPath $definition.SourcePath -Destination $entrypointPath

  try {
    $compiledPath = Join-Path $compileRoot 'compiled.swf'
    $normalizedPath = Join-Path $compileRoot $definition.OutputFile
    Invoke-CanvasCompilation `
      -JavaPath $resolvedJavaPath `
      -MxmlcJarPath $mxmlcJarPath `
      -FlexConfigPath $flexConfigPath `
      -PlayerGlobalPath $playerGlobalMatches[0].FullName `
      -FlexFrameworksPath $flexFrameworksPath `
      -EntrypointPath $entrypointPath `
      -SourceRoot $sourceRoot `
      -OutputPath $compiledPath `
      -StageWidth $definition.StageWidth `
      -StageHeight $definition.StageHeight `
      -FrameRate $definition.FrameRate
    Normalize-CanvasMovie `
      -JavaPath $resolvedJavaPath `
      -JpexsJarPath $resolvedJpexsJarPath `
      -InputPath $compiledPath `
      -OutputPath $normalizedPath `
      -WorkPath $compileRoot
    [void](Assert-CanvasMovie `
      -JavaPath $resolvedJavaPath `
      -JpexsJarPath $resolvedJpexsJarPath `
      -MoviePath $normalizedPath `
      -WorkPath $compileRoot `
      -Definition $definition)
    $destinationPath = Join-Path $resolvedOutputDirectory $definition.OutputFile
    Publish-CanvasScaleformFile -CandidatePath $normalizedPath -DestinationPath $destinationPath -AllowedRoot $resolvedOutputDirectory
    return [pscustomobject]@{
      Name = $definition.Name
      Role = $definition.Role
      OutputFile = $definition.OutputFile
      Path = $destinationPath
    }
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Canvas build files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-CanvasRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}

function Assert-CanvasNotGitLfsPointer {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $prefixLength = [Math]::Min($bytes.Length, 128)
  $prefix = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $prefixLength)
  if ($prefix.StartsWith('version https://git-lfs.github.com/spec/v1', [System.StringComparison]::Ordinal)) {
    throw "$Description is a Git LFS pointer instead of materialized content: $Path"
  }
}

function Get-CanvasGeneralBa2Entries {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $stream = [System.IO.File]::OpenRead($Path)
  $reader = [System.IO.BinaryReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
  try {
    if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'BTDX') {
      throw "Archive is missing the BTDX signature: $Path"
    }
    $version = $reader.ReadUInt32()
    $archiveType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
    $fileCount = $reader.ReadUInt32()
    $nameTableOffset = $reader.ReadUInt64()
    if ($version -ne 2 -or $archiveType -cne 'GNRL' -or
        $fileCount -gt 10000 -or $nameTableOffset -ge [uint64]$stream.Length) {
      throw "Archive is not a supported version 2 General BA2: $Path"
    }
    [void]$reader.ReadUInt64()

    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $fileCount; $index++) {
      [void]$reader.ReadUInt32()
      [void]$reader.ReadBytes(4)
      [void]$reader.ReadUInt32()
      [void]$reader.ReadUInt32()
      $offset = $reader.ReadUInt64()
      $packedSize = $reader.ReadUInt32()
      $unpackedSize = $reader.ReadUInt32()
      [void]$reader.ReadUInt32()
      $storedSize = if ($packedSize -eq 0) { $unpackedSize } else { $packedSize }
      if ($offset -lt 32 + ($fileCount * 36) -or
          $offset + $storedSize -gt $nameTableOffset) {
        throw "Archive contains an invalid file record at index ${index}: $Path"
      }
      $records.Add([pscustomobject]@{
        Offset = $offset
        PackedSize = $packedSize
        UnpackedSize = $unpackedSize
      })
    }

    $stream.Position = [int64]$nameTableOffset
    for ($index = 0; $index -lt $fileCount; $index++) {
      $nameLength = $reader.ReadUInt16()
      if ($nameLength -eq 0 -or $stream.Position + $nameLength -gt $stream.Length) {
        throw "Archive contains an invalid name record at index ${index}: $Path"
      }
      $name = [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($nameLength)).Replace('\', '/')
      $records[$index] | Add-Member -NotePropertyName Name -NotePropertyValue $name
      $records[$index] | Add-Member -NotePropertyName ArchivePath -NotePropertyValue $Path
    }
    return @($records)
  }
  finally {
    $reader.Dispose()
    $stream.Dispose()
  }
}

function Read-CanvasGeneralBa2EntryBytes {
  param(
    [Parameter(Mandatory = $true)]
    [psobject]$Entry
  )

  $stream = [System.IO.File]::OpenRead([string]$Entry.ArchivePath)
  try {
    $stream.Position = [int64]$Entry.Offset
    $storedSize = if ([uint32]$Entry.PackedSize -eq 0) {
      [uint32]$Entry.UnpackedSize
    }
    else {
      [uint32]$Entry.PackedSize
    }
    $storedBytes = [byte[]]::new([int]$storedSize)
    $readCount = $stream.Read($storedBytes, 0, $storedBytes.Length)
    if ($readCount -ne $storedBytes.Length) {
      throw "Unable to read BA2 entry '$($Entry.Name)' from $($Entry.ArchivePath)."
    }
  }
  finally {
    $stream.Dispose()
  }

  if ([uint32]$Entry.PackedSize -ne 0) {
    throw "Canvas BA2 entry '$($Entry.Name)' is compressed; uncompressed General archives are required."
  }
  return $storedBytes
}

. (Join-Path $PSScriptRoot 'sharedCanvasPackaging.ps1')
