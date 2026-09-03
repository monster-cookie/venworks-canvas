$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-ConsumerDiscoveryRequiredFile {
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

function Resolve-ConsumerDiscoveryRequiredDirectory {
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

function Write-ConsumerDiscoveryUtf8WithoutBom {
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

function Get-ConsumerDiscoveryFileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-ConsumerDiscoveryReviewFileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($extension -notin @('.json', '.yaml', '.yml')) {
    return Get-ConsumerDiscoveryFileSha256 -Path $Path
  }

  $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
  $text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($Path))
  $canonicalText = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  $canonicalBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($canonicalText)
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($canonicalBytes))
}

function Get-ConsumerDiscoveryDirectoryDigest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $resolvedRoot = Resolve-ConsumerDiscoveryRequiredDirectory -Path $Path -Description 'Directory digest root'
  $digestRows = @(
    Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | ForEach-Object {
      $relativePath = [System.IO.Path]::GetRelativePath($resolvedRoot, $_.FullName).Replace('\', '/')
      "$relativePath`:$((Get-ConsumerDiscoveryReviewFileSha256 -Path $_.FullName))"
    } | Sort-Object
  )
  $digestText = [string]::Join("`n", $digestRows) + "`n"
  $digestBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($digestText)
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($digestBytes))
}

function Assert-ConsumerDiscoveryRemovalPath {
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
    throw "Refusing to remove path outside the consumer-discovery work root: $fullPath"
  }
}

function Get-ConsumerDiscoveryMatrix {
  param(
    [string]$RepositoryRoot = ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')))
  )

  $matrixPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $RepositoryRoot 'Scaleform\probes\consumer-discovery\probe-matrix.psd1') `
    -Description 'Consumer-discovery probe matrix'
  return Import-PowerShellDataFile -LiteralPath $matrixPath
}

function Resolve-ConsumerDiscoveryProfile {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Matrix,

    [Alias('Profile')]
    [string]$ProbeProfile
  )

  $profileKey = $ProbeProfile
  if ([string]::IsNullOrWhiteSpace($profileKey)) {
    $profileKey = [string]$Matrix.DefaultProfile
  }
  $profileMatches = @($Matrix.Profiles | Where-Object { [string]$_.Key -ceq $profileKey })
  if ($profileMatches.Count -ne 1) {
    $available = [string]::Join(', ', @($Matrix.Profiles | ForEach-Object { [string]$_.Key }))
    throw "Unknown consumer-discovery profile '$profileKey'. Expected exactly one of: $available."
  }
  return $profileMatches[0]
}

function Import-ConsumerDiscoveryEnvironment {
  param(
    [string]$Path = (Join-Path ([System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))) '.env')
  )

  $environmentPath = Resolve-ConsumerDiscoveryRequiredFile -Path $Path -Description 'Consumer-discovery environment file'
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

function Resolve-ConsumerDiscoveryExecutable {
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
  return Resolve-ConsumerDiscoveryRequiredFile -Path $candidate -Description $Description
}

function Assert-PinnedVwHudToolchainFixture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VwHudRepositoryPath,

    [Parameter(Mandatory = $true)]
    [hashtable]$Matrix
  )

  $resolvedRoot = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path $VwHudRepositoryPath `
    -Description 'VWHUD repository'
  $safeDirectory = $resolvedRoot.Replace('\', '/')
  $headOutput = @(& git -c "safe.directory=$safeDirectory" -C $resolvedRoot rev-parse HEAD)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the VWHUD fixture revision from $resolvedRoot."
  }
  $head = ([string]::Join('', $headOutput)).Trim()
  if ($head -cne [string]$Matrix.VwHudFixture.Revision) {
    throw "VWHUD fixture drifted. Expected $($Matrix.VwHudFixture.Revision); found $head."
  }
  $status = @(& git -c "safe.directory=$safeDirectory" -C $resolvedRoot status --porcelain=v1)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect the VWHUD fixture worktree at $resolvedRoot."
  }
  if ($status.Count -ne 0) {
    throw "VWHUD fixture worktree is not clean: $([string]::Join(', ', $status))"
  }
  foreach ($relativePath in @($Matrix.VwHudFixture.RequiredToolchainFiles)) {
    [void](Resolve-ConsumerDiscoveryRequiredFile `
      -Path (Join-Path $resolvedRoot ([string]$relativePath)) `
      -Description "Required pinned VWHUD toolchain file '$relativePath'")
  }
  return $resolvedRoot
}

function Assert-PinnedVenworksCoreFixture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VenworksCoreRepositoryPath,

    [Parameter(Mandatory = $true)]
    [hashtable]$Matrix
  )

  $resolvedRoot = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path $VenworksCoreRepositoryPath `
    -Description 'Venworks Core repository'
  $safeDirectory = $resolvedRoot.Replace('\', '/')
  $headOutput = @(& git -c "safe.directory=$safeDirectory" -C $resolvedRoot rev-parse HEAD)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read the Venworks Core fixture revision from $resolvedRoot."
  }
  $head = ([string]::Join('', $headOutput)).Trim()
  if ($head -cne [string]$Matrix.VenworksCoreFixture.Revision) {
    throw "Venworks Core fixture drifted. Expected $($Matrix.VenworksCoreFixture.Revision); found $head."
  }

  $requiredDefinitions = @($Matrix.VenworksCoreFixture.SourceFiles) + @($Matrix.VenworksCoreFixture.RuntimeScripts)
  $requiredPaths = @($requiredDefinitions | ForEach-Object {
    if ($_.ContainsKey('Path')) { [string]$_.Path } else { [string]$_.Source }
  })
  $status = @(& git -c "safe.directory=$safeDirectory" -C $resolvedRoot status --porcelain=v1 -- @requiredPaths)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect the required Venworks Core fixture paths at $resolvedRoot."
  }
  if ($status.Count -ne 0) {
    throw "Required Venworks Core fixture paths are not clean: $([string]::Join(', ', $status))"
  }

  foreach ($definition in $requiredDefinitions) {
    $relativePath = if ($definition.ContainsKey('Path')) { [string]$definition.Path } else { [string]$definition.Source }
    $path = Resolve-ConsumerDiscoveryRequiredFile `
      -Path (Join-Path $resolvedRoot $relativePath) `
      -Description "Required pinned Venworks Core file '$relativePath'"
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -cne [string]$definition.Sha256) {
      throw "Venworks Core fixture hash drifted for '$relativePath'. Expected $($definition.Sha256); found $actualHash."
    }
  }

  return $resolvedRoot
}

function Get-VwHudExpectedMovieHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VwHudRepositoryPath,

    [Parameter(Mandatory = $true)]
    [string]$ManifestRelativePath
  )

  $manifestPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $VwHudRepositoryPath $ManifestRelativePath) `
    -Description 'VWHUD host movie manifest'
  [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
  $expectedHashFile = [string]$manifest.scaleformBuild.expectedHashFile
  if ([string]::IsNullOrWhiteSpace($expectedHashFile)) {
    throw "VWHUD host movie manifest does not declare expectedHashFile: $manifestPath"
  }
  $hashPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path (Split-Path -Parent $manifestPath) $expectedHashFile) `
    -Description 'VWHUD expected host movie hash'
  $hashLine = [System.IO.File]::ReadAllText($hashPath).Trim()
  $hashMatch = [regex]::Match($hashLine, '^(?<hash>[0-9A-Fa-f]{64})(?:\s{2,}.+)?$')
  if (!$hashMatch.Success) {
    throw "VWHUD expected host movie hash is invalid: $hashPath"
  }
  return $hashMatch.Groups['hash'].Value.ToUpperInvariant()
}

function Get-VwHudHostMovieEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [string]$VwHudRepositoryPath,

    [Parameter(Mandatory = $true)]
    [hashtable]$Matrix
  )

  $evidence = [System.Collections.Generic.List[object]]::new()
  foreach ($definition in @($Matrix.VwHudFixture.PlayerHudMovies)) {
    $sourcePath = Resolve-ConsumerDiscoveryRequiredFile `
      -Path (Join-Path $VwHudRepositoryPath ([string]$definition.Source)) `
      -Description "Pinned VWHUD host movie '$($definition.Source)'"
    $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $evidence.Add([pscustomobject]@{
      Source = [string]$definition.Source
      Target = [string]$definition.Target
      Sha256 = $actualHash
    })
  }
  return @($evidence)
}

function Invoke-ConsumerDiscoveryJavaJar {
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

function Normalize-ConsumerDiscoveryMovie {
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
  Invoke-ConsumerDiscoveryJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-swf2xml', $InputPath, $rawXmlPath) `
    -Description 'JPEXS consumer-discovery movie XML export'

  [xml]$movie = Get-Content -LiteralPath $rawXmlPath -Raw
  $tagsNode = $movie.SelectSingleNode('/swf/tags')
  if ($null -eq $tagsNode) {
    throw 'Generated consumer-discovery movie does not contain a root tag collection.'
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

  Invoke-ConsumerDiscoveryJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-xml2swf', $normalizedXmlPath, $OutputPath) `
    -Description 'JPEXS normalized consumer-discovery movie rebuild'
}

function Get-ConsumerDiscoveryClassInventory {
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
        throw "Consumer-discovery movie exports duplicate definition '$qualifiedName'."
      }
    }
  }

  [string[]]$inventory = @($definitions)
  [System.Array]::Sort($inventory, [System.StringComparer]::Ordinal)
  if ($inventory.Count -eq 0) {
    throw 'Consumer-discovery movie did not export any ActionScript definitions.'
  }
  return $inventory
}

function Get-ConsumerDiscoveryBuildDefinition {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
  )

  $resolvedManifestPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path $ManifestPath `
    -Description 'Consumer-discovery movie build manifest'
  [xml]$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw
  $build = $manifest.canvasDiscoveryMovieBuild
  if ($null -eq $build -or
      [string]::IsNullOrWhiteSpace([string]$build.name) -or
      [string]::IsNullOrWhiteSpace([string]$build.role) -or
      [string]::IsNullOrWhiteSpace([string]$build.outputFile) -or
      [string]::IsNullOrWhiteSpace([string]$build.documentClass) -or
      [string]::IsNullOrWhiteSpace([string]$build.className) -or
      [int]$build.stageWidth -le 0 -or
      [int]$build.stageHeight -le 0 -or
      [int]$build.frameRate -le 0) {
    throw "Invalid consumer-discovery movie build manifest: $resolvedManifestPath"
  }
  $manifestDirectory = Split-Path -Parent $resolvedManifestPath
  $requiredTokens = @($build.requiredTokens.token | ForEach-Object { [string]$_ })
  $forbiddenTokens = @($build.forbiddenTokens.token | ForEach-Object { [string]$_ })
  if ($requiredTokens.Count -eq 0 -or $forbiddenTokens.Count -eq 0) {
    throw "Consumer-discovery movie manifest must declare required and forbidden tokens: $resolvedManifestPath"
  }
  return [pscustomobject]@{
    Name = [string]$build.name
    Role = [string]$build.role
    OutputFile = [string]$build.outputFile
    ManifestPath = $resolvedManifestPath
    SourcePath = Resolve-ConsumerDiscoveryRequiredFile `
      -Path (Join-Path $manifestDirectory ([string]$build.documentClass)) `
      -Description 'Consumer-discovery ActionScript entrypoint'
    ClassName = [string]$build.className
    StageWidth = [int]$build.stageWidth
    StageHeight = [int]$build.stageHeight
    FrameRate = [int]$build.frameRate
    RequiredTokens = $requiredTokens
    ForbiddenTokens = $forbiddenTokens
  }
}

function Invoke-ConsumerDiscoveryCompilation {
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
    Invoke-ConsumerDiscoveryJavaJar `
      -JavaPath $JavaPath `
      -JarPath $MxmlcJarPath `
      -Arguments $compilerArguments `
      -Description 'Apache Flex consumer-discovery compilation'
  }
  finally {
    Pop-Location
  }
}

function Assert-ConsumerDiscoveryMovie {
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
    [pscustomobject]$Definition,

    [Parameter(Mandatory = $true)]
    [string]$PassName
  )

  $metadata = Get-ScaleformMovieMetadata `
    -Path $MoviePath `
    -Context "Generated $($Definition.Name) consumer-discovery movie" `
    -ExpectedSignature CWS
  if ($metadata.StageWidth -ne $Definition.StageWidth -or
      $metadata.StageHeight -ne $Definition.StageHeight -or
      $metadata.FrameRate -ne $Definition.FrameRate -or
      $metadata.FrameCount -ne 1) {
    throw "Consumer-discovery movie '$($Definition.Name)' has unexpected stage metadata."
  }

  $exportDirectory = Join-Path $WorkPath "$PassName-scripts"
  Invoke-ConsumerDiscoveryJavaJar `
    -JavaPath $JavaPath `
    -JarPath $JpexsJarPath `
    -Arguments @('-format', 'script:as', '-export', 'script', $exportDirectory, $MoviePath) `
    -Description "JPEXS $($Definition.Name) ActionScript export"
  $inventory = @(Get-ConsumerDiscoveryClassInventory -ScriptsDirectory $exportDirectory)
  if ($inventory.Count -ne 1 -or $inventory[0] -cne $Definition.ClassName) {
    throw "Consumer-discovery movie '$($Definition.Name)' exports unexpected classes: $([string]::Join(', ', $inventory))"
  }
  $validationSource = @(Get-ChildItem -LiteralPath $exportDirectory -Recurse -File -Filter '*.as' | ForEach-Object {
    [System.IO.File]::ReadAllText($_.FullName)
  }) -join "`n"
  foreach ($requiredToken in @($Definition.RequiredTokens)) {
    if (!$validationSource.Contains([string]$requiredToken)) {
      throw "Consumer-discovery movie '$($Definition.Name)' is missing required bytecode token '$requiredToken'."
    }
  }
  foreach ($forbiddenToken in @($Definition.ForbiddenTokens)) {
    if ($validationSource.Contains([string]$forbiddenToken)) {
      throw "Consumer-discovery movie '$($Definition.Name)' contains forbidden bytecode token '$forbiddenToken'."
    }
  }
  return [pscustomobject]@{
    ClassInventory = $inventory
    Metadata = $metadata
  }
}

function Invoke-ConsumerDiscoveryMovieBuild {
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

  $resolvedManifestPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path $ManifestPath `
    -Description 'Consumer-discovery movie build manifest'
  $manifestSha256Before = (Get-FileHash -LiteralPath $resolvedManifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
  $definition = Get-ConsumerDiscoveryBuildDefinition -ManifestPath $resolvedManifestPath
  if ((Get-FileHash -LiteralPath $resolvedManifestPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $manifestSha256Before) {
    throw "Consumer-discovery movie manifest changed while it was being parsed: $resolvedManifestPath"
  }
  $sourceSha256Before = (Get-FileHash -LiteralPath $definition.SourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $resolvedJavaPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-ConsumerDiscoveryRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-ConsumerDiscoveryRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  $mxmlcJarPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $resolvedFlexSdkPath 'lib\mxmlc.jar') `
    -Description 'Apache Flex mxmlc compiler'
  $flexFrameworksPath = Resolve-ConsumerDiscoveryRequiredDirectory `
    -Path (Join-Path $resolvedFlexSdkPath 'frameworks') `
    -Description 'Apache Flex frameworks directory'
  $flexConfigPath = Resolve-ConsumerDiscoveryRequiredFile `
    -Path (Join-Path $flexFrameworksPath 'flex-config.xml') `
    -Description 'Apache Flex compiler configuration'
  $playerGlobalMatches = @(Get-ChildItem -LiteralPath $flexFrameworksPath -Recurse -File -Filter 'playerglobal.swc')
  if ($playerGlobalMatches.Count -ne 1) {
    throw "Expected exactly one playerglobal.swc in the VWHUD v2 Flex SDK; found $($playerGlobalMatches.Count)."
  }

  $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
  New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkDirectory | Out-Null
  $buildWorkDirectory = Join-Path $resolvedWorkDirectory ([guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $buildWorkDirectory | Out-Null
  $sourceRoot = Join-Path $buildWorkDirectory 'source'
  $firstPassRoot = Join-Path $buildWorkDirectory 'first-pass'
  $secondPassRoot = Join-Path $buildWorkDirectory 'second-pass'
  New-Item -ItemType Directory -Path $sourceRoot, $firstPassRoot, $secondPassRoot | Out-Null
  $entrypointPath = Join-Path $sourceRoot ([System.IO.Path]::GetFileName($definition.SourcePath))
  Copy-Item -LiteralPath $definition.SourcePath -Destination $entrypointPath
  if ((Get-FileHash -LiteralPath $entrypointPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $sourceSha256Before) {
    throw "Consumer-discovery ActionScript changed while its build snapshot was being captured: $($definition.SourcePath)"
  }

  try {
    $passResults = [System.Collections.Generic.List[object]]::new()
    foreach ($pass in @(
      [pscustomobject]@{ Name = 'first'; Root = $firstPassRoot },
      [pscustomobject]@{ Name = 'second'; Root = $secondPassRoot }
    )) {
      $compiledPath = Join-Path $pass.Root 'compiled.swf'
      $normalizedPath = Join-Path $pass.Root $definition.OutputFile
      Invoke-ConsumerDiscoveryCompilation `
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
      Normalize-ConsumerDiscoveryMovie `
        -JavaPath $resolvedJavaPath `
        -JpexsJarPath $resolvedJpexsJarPath `
        -InputPath $compiledPath `
        -OutputPath $normalizedPath `
        -WorkPath $pass.Root
      $inspection = Assert-ConsumerDiscoveryMovie `
        -JavaPath $resolvedJavaPath `
        -JpexsJarPath $resolvedJpexsJarPath `
        -MoviePath $normalizedPath `
        -WorkPath $pass.Root `
        -Definition $definition `
        -PassName $pass.Name
      $passResults.Add([pscustomobject]@{
        Path = $normalizedPath
        Sha256 = (Get-FileHash -LiteralPath $normalizedPath -Algorithm SHA256).Hash.ToUpperInvariant()
        ClassInventory = @($inspection.ClassInventory)
      })
    }

    if ($passResults[0].Sha256 -cne $passResults[1].Sha256) {
      throw "Consumer-discovery movie '$($definition.Name)' is not deterministic across two v2-style normalized builds."
    }
    if ([string]::Join("`n", $passResults[0].ClassInventory) -cne
        [string]::Join("`n", $passResults[1].ClassInventory)) {
      throw "Consumer-discovery movie '$($definition.Name)' changed class inventory across deterministic build passes."
    }

    $destinationPath = Join-Path $resolvedOutputDirectory $definition.OutputFile
    Copy-Item -LiteralPath $passResults[1].Path -Destination $destinationPath -Force
    Write-ConsumerDiscoveryUtf8WithoutBom `
      -Path "$destinationPath.sha256" `
      -Text ($passResults[1].Sha256 + "`n")
    Write-ConsumerDiscoveryUtf8WithoutBom `
      -Path "$destinationPath.classes.txt" `
      -Text ([string]::Join("`n", $passResults[1].ClassInventory) + "`n")
    if ((Get-FileHash -LiteralPath $definition.ManifestPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $manifestSha256Before -or
        (Get-FileHash -LiteralPath $definition.SourcePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $sourceSha256Before) {
      throw "Consumer-discovery movie '$($definition.Name)' source inputs changed during compilation; generated evidence was not accepted."
    }
    return [pscustomobject]@{
      Name = $definition.Name
      Role = $definition.Role
      OutputFile = $definition.OutputFile
      Path = $destinationPath
      Sha256 = $passResults[1].Sha256
      ManifestPath = $definition.ManifestPath
      ManifestSha256 = $manifestSha256Before
      SourcePath = $definition.SourcePath
      SourceSha256 = $sourceSha256Before
      ClassInventory = @($passResults[1].ClassInventory)
      BuildPasses = 2
    }
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Consumer-discovery build files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-ConsumerDiscoveryRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}

function Assert-ConsumerDiscoveryNotGitLfsPointer {
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

function Get-ConsumerDiscoveryGeneralBa2Entries {
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

function Read-ConsumerDiscoveryGeneralBa2EntryBytes {
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
    throw "Consumer-discovery BA2 entry '$($Entry.Name)' is compressed; uncompressed General archives are required."
  }
  return $storedBytes
}
