$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-BuildExactNames {
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

function Resolve-BuildRequiredFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $resolved -or !(Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
    throw "$Description does not exist: $Path"
  }
  return $resolved.Path
}

function Assert-BuildPapyrusFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = Resolve-BuildRequiredFile -Path $Path -Description $Description
  $header = [byte[]]::new(16)
  $stream = [IO.File]::OpenRead($resolvedPath)
  try {
    if ($stream.Length -lt $header.Length -or $stream.Read($header, 0, $header.Length) -ne $header.Length) {
      throw "$Description is empty or too short to contain a Papyrus PEX header: $resolvedPath"
    }
  }
  finally {
    $stream.Dispose()
  }
  $signature = [BitConverter]::ToString($header, 0, 4)
  if ($signature -cne 'DE-C0-57-FA') {
    throw "$Description has an unsupported Papyrus PEX header '$signature': $resolvedPath"
  }
  return $resolvedPath
}

function Assert-BuildScaleformFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedPath = Resolve-BuildRequiredFile -Path $Path -Description $Description
  $header = [byte[]]::new(8)
  $stream = [IO.File]::OpenRead($resolvedPath)
  try {
    if ($stream.Length -lt $header.Length -or $stream.Read($header, 0, $header.Length) -ne $header.Length) {
      throw "$Description is empty or too short to be a Scaleform movie: $resolvedPath"
    }
  }
  finally {
    $stream.Dispose()
  }
  $signature = [Text.Encoding]::ASCII.GetString($header, 0, 3)
  if ($signature -cnotin @('FWS', 'CWS', 'ZWS', 'GFX', 'CFX')) {
    throw "$Description has an unsupported Scaleform header '$signature': $resolvedPath"
  }
  return $resolvedPath
}

function Resolve-BuildRequiredDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if ($null -eq $resolved -or !(Test-Path -LiteralPath $resolved.Path -PathType Container)) {
    throw "$Description does not exist: $Path"
  }
  return $resolved.Path
}

function Get-BuildNormalizedFullPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'A filesystem path cannot be empty.'
  }

  $fullPath = [IO.Path]::GetFullPath($Path)
  $pathRoot = [IO.Path]::GetPathRoot($fullPath)
  if ($fullPath.Length -gt $pathRoot.Length) {
    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  }
  return $fullPath
}

function Test-BuildSamePath {
  param(
    [Parameter(Mandatory = $true)][string]$Left,
    [Parameter(Mandatory = $true)][string]$Right
  )

  return [string]::Equals(
    (Get-BuildNormalizedFullPath -Path $Left),
    (Get-BuildNormalizedFullPath -Path $Right),
    [StringComparison]::OrdinalIgnoreCase
  )
}

function Test-BuildOverlappingPaths {
  param(
    [Parameter(Mandatory = $true)][string]$Left,
    [Parameter(Mandatory = $true)][string]$Right
  )

  $leftPath = Get-BuildNormalizedFullPath -Path $Left
  $rightPath = Get-BuildNormalizedFullPath -Path $Right
  if ([string]::Equals($leftPath, $rightPath, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $leftPrefix = $leftPath + [IO.Path]::DirectorySeparatorChar
  $rightPrefix = $rightPath + [IO.Path]::DirectorySeparatorChar
  return $leftPath.StartsWith($rightPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $rightPath.StartsWith($leftPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Write-BuildUtf8WithoutBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
  )

  $canonicalText = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [IO.File]::WriteAllText($Path, $canonicalText, [Text.UTF8Encoding]::new($false))
}

function Assert-BuildArtifactHeader {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  $resolvedPath = Resolve-BuildRequiredFile -Path $Path -Description 'Build artifact'
  $stream = [IO.File]::OpenRead($resolvedPath)
  try {
    $header = [byte[]]::new(24)
    $read = $stream.Read($header, 0, $header.Length)
    $prefix = [Text.Encoding]::ASCII.GetString($header, 0, $read)
    if ($prefix.StartsWith('version https://git-lfs', [StringComparison]::Ordinal)) {
      throw "Artifact is a Git LFS pointer, not a deployed binary: $resolvedPath"
    }
    if ($read -ne 24) {
      throw "Artifact header is truncated: $resolvedPath"
    }
    $magic = [Text.Encoding]::ASCII.GetString($header, 0, 4)
    switch ([IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()) {
      '.esm' {
        $recordBytes = [BitConverter]::ToUInt32($header, 4)
        if ($magic -cne 'TES4' -or $recordBytes -lt 18 -or [long]$recordBytes + 24 -gt $stream.Length) {
          throw "Invalid or truncated ESM header: $resolvedPath"
        }
      }
      '.ba2' {
        $version = [BitConverter]::ToUInt32($header, 4)
        $archiveType = [Text.Encoding]::ASCII.GetString($header, 8, 4)
        $fileCount = [BitConverter]::ToUInt32($header, 12)
        $nameOffset = [BitConverter]::ToUInt64($header, 16)
        $minimumRecordEnd = if ($archiveType -ceq 'GNRL') { 32L + (36L * $fileCount) } else { 32L }
        if ($magic -cne 'BTDX' -or $version -ne 2 -or $archiveType -cnotin @('GNRL', 'DX10') -or $fileCount -eq 0 -or
            $nameOffset -lt $minimumRecordEnd -or $nameOffset -ge [uint64]$stream.Length -or
            $nameOffset + (2L * $fileCount) -gt [uint64]$stream.Length) {
          throw "Invalid or truncated BA2 header: $resolvedPath"
        }
      }
      default { throw "Unsupported artifact extension: $resolvedPath" }
    }
  }
  finally {
    $stream.Dispose()
  }
}

function Get-BuildFileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-BuildRemovalPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $fullPath = Get-BuildNormalizedFullPath -Path $Path
  $fullRoot = Get-BuildNormalizedFullPath -Path $AllowedRoot
  $prefix = $fullRoot + [IO.Path]::DirectorySeparatorChar
  if (!$fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove path outside the allowed build root: $fullPath"
  }
}

function Import-BuildEnvironment {
  param([Parameter(Mandatory = $true)][string]$Path)

  $environmentPath = Resolve-BuildRequiredFile -Path $Path -Description 'Build environment file'
  foreach ($line in [IO.File]::ReadAllLines($environmentPath)) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
      continue
    }

    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) {
      throw "Invalid environment entry in $environmentPath. Expected NAME=VALUE."
    }
    $name = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    if ($name -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
      throw "Invalid environment variable name '$name' in $environmentPath."
    }
    if ($value.Length -ge 2 -and
        (($value.StartsWith('"') -and $value.EndsWith('"')) -or
         ($value.StartsWith("'") -and $value.EndsWith("'")))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($name, $value, 'Process')
  }
}

function Resolve-BuildExecutable {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $candidate = $Path
  if (Test-Path -LiteralPath $Path -PathType Container) {
    $candidate = Join-Path $Path $FileName
  }
  return Resolve-BuildRequiredFile -Path $candidate -Description $Description
}

function Get-BuildStagingSelection {
  param([string[]]$VariantKeys)

  return @(Get-ModuleVariants -VariantKeys $VariantKeys)
}

function Get-BuildPapyrusSources {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object]$Variant,
    [string]$SourceRoot
  )

  if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    if ($null -eq $Global:BuildSettings -or [string]::IsNullOrWhiteSpace([string]$Global:BuildSettings.PapyrusSourceRoot)) {
      throw 'BuildSettings.PapyrusSourceRoot must be configured.'
    }
    $SourceRoot = [string]$Global:BuildSettings.PapyrusSourceRoot
  }
  $resolvedSourceRoot = Resolve-BuildRequiredDirectory -Path $SourceRoot -Description 'Papyrus source root'

  $namespace = [string]$Variant.PapyrusNamespace
  if ([string]::IsNullOrWhiteSpace($namespace)) {
    throw "Module variant '$($Variant.VariantKey)' does not configure a Papyrus namespace."
  }
  $namespaceSegments = @($namespace.Split(':'))
  if ($namespaceSegments.Count -eq 0 -or
      @($namespaceSegments | Where-Object { $_ -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' }).Count -ne 0) {
    throw "Module variant '$($Variant.VariantKey)' has invalid Papyrus namespace '$namespace'."
  }
  $namespaceRelativePath = [string]::Join([IO.Path]::DirectorySeparatorChar, $namespaceSegments)
  $namespaceRoot = Resolve-BuildRequiredDirectory `
    -Path (Join-Path $resolvedSourceRoot $namespaceRelativePath) `
    -Description "Papyrus namespace '$namespace'"

  $sources = @(Get-ChildItem -LiteralPath $namespaceRoot -Recurse -File | Where-Object {
    $_.Extension -ieq '.psc'
  } | Sort-Object FullName)
  foreach ($source in $sources) {
    $relativeSource = [IO.Path]::GetRelativePath($resolvedSourceRoot, $source.FullName)
    $extension = [IO.Path]::GetExtension($relativeSource)
    $expectedScriptName = $relativeSource.Substring(0, $relativeSource.Length - $extension.Length).Replace([IO.Path]::DirectorySeparatorChar, ':').Replace([IO.Path]::AltDirectorySeparatorChar, ':')
    $sourceText = [IO.File]::ReadAllText($source.FullName)
    $declaration = [regex]::Match($sourceText, '(?im)^\s*ScriptName\s+([A-Za-z_][A-Za-z0-9_:]*)\b')
    if (!$declaration.Success) {
      throw "Papyrus source '$relativeSource' does not declare ScriptName."
    }
    if (![string]::Equals($declaration.Groups[1].Value, $expectedScriptName, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Papyrus source '$relativeSource' declares '$($declaration.Groups[1].Value)' instead of '$expectedScriptName'."
    }

    [pscustomobject]@{
      Source = $source.FullName
      RelativeSource = $relativeSource
      RelativeOutput = [IO.Path]::ChangeExtension($relativeSource, '.pex')
    }
  }
}

function Resolve-BuildVariantInstallPath {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object]$Variant)

  $variableName = [string]$Variant.EnvironmentVariableName
  if ([string]::IsNullOrWhiteSpace($variableName)) {
    throw "Module variant '$($Variant.VariantKey)' does not configure an installation environment variable."
  }
  $configuredPath = [Environment]::GetEnvironmentVariable($variableName, 'Process')
  if ([string]::IsNullOrWhiteSpace($configuredPath)) {
    throw "Module variant '$($Variant.VariantKey)' installation path is not configured. Set $variableName."
  }
  return Get-BuildNormalizedFullPath -Path $configuredPath
}

function Invoke-BuildJavaJar {
  param(
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JarPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$Description
  )

  & $JavaPath -jar $JarPath @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE."
  }
}
