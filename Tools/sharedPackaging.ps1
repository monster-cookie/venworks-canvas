$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-BuildPackagePropertyValue {
  param(
    [Parameter(Mandatory = $true)][object]$InputObject,
    [Parameter(Mandatory = $true)][string]$Name,
    [object]$DefaultValue = $null
  )

  if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
    return $InputObject[$Name]
  }
  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) { return $DefaultValue }
  return $property.Value
}

function Assert-BuildPackageLeafName {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Extension,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if ([string]::IsNullOrWhiteSpace($Name) -or
      [IO.Path]::IsPathRooted($Name) -or
      $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
      $Name.Contains([IO.Path]::DirectorySeparatorChar) -or
      $Name.Contains([IO.Path]::AltDirectorySeparatorChar) -or
      ![string]::Equals([IO.Path]::GetExtension($Name), $Extension, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description must be a leaf $Extension filename: '$Name'."
  }
}

function Resolve-BuildArchiveTarget {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [AllowEmptyString()][Parameter(Mandatory = $true)][string]$Target,
    [switch]$AllowRoot
  )

  $rootPath = Get-BuildNormalizedFullPath -Path $Root
  if ([string]::IsNullOrWhiteSpace($Target)) {
    if (!$AllowRoot) { throw 'Archive payload target cannot be empty for a file source.' }
    return $rootPath
  }
  if ([IO.Path]::IsPathRooted($Target) -or $Target.Contains(':')) {
    throw "Archive payload target must be a non-rooted relative path: '$Target'."
  }
  $segments = $Target.Split([char[]]@('\', '/'), [StringSplitOptions]::None)
  if (@($segments | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
    throw "Archive payload target contains an empty or traversal segment: '$Target'."
  }
  $targetPath = [IO.Path]::GetFullPath((Join-Path $rootPath $Target))
  if (!$targetPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Archive payload target escapes its package root: '$Target'."
  }
  return $targetPath
}

function Resolve-BuildPackageAssetSource {
  param(
    [Parameter(Mandatory = $true)][object]$Asset,
    [Parameter(Mandatory = $true)][object]$Variant,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [AllowEmptyString()][string]$ScaleformDirectory
  )

  $rootName = [string](Get-BuildPackagePropertyValue -InputObject $Asset -Name 'Root')
  $relativeSource = [string](Get-BuildPackagePropertyValue -InputObject $Asset -Name 'Source')
  if ([string]::IsNullOrWhiteSpace($relativeSource) -or [IO.Path]::IsPathRooted($relativeSource) -or $relativeSource.Contains(':')) {
    throw "Package asset Source must be a non-rooted relative path: '$relativeSource'."
  }
  $segments = $relativeSource.Split([char[]]@('\', '/'), [StringSplitOptions]::None)
  if ($relativeSource -cne '.' -and @($segments | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
    throw "Package asset Source contains an empty or traversal segment: '$relativeSource'."
  }
  $effectiveRootName = $rootName
  $sourceRoot = switch ($rootName) {
    'Repository' { $RepositoryRoot }
    'Scaleform' {
      if ([string]::IsNullOrWhiteSpace($ScaleformDirectory)) {
        $target = [string](Get-BuildPackagePropertyValue -InputObject $Asset -Name 'Target' -DefaultValue '')
        [void](Resolve-BuildArchiveTarget -Root ([string]$Variant.StagingFolderPath) -Target $target)
        $relativeSource = $target
        $segments = $relativeSource.Split([char[]]@('\', '/'), [StringSplitOptions]::None)
        $effectiveRootName = 'Staging'
        [string]$Variant.StagingFolderPath
      }
      else { $ScaleformDirectory }
    }
    'Staging' { [string]$Variant.StagingFolderPath }
    default { throw "Unknown package asset Root '$rootName'. Expected Repository, Scaleform, or Staging." }
  }
  $resolvedRoot = Resolve-BuildRequiredDirectory -Path $sourceRoot -Description "$($Variant.VariantKey) package asset root '$rootName'"
  $sourcePath = if ($relativeSource -ceq '.') { $resolvedRoot } else { [IO.Path]::GetFullPath((Join-Path $resolvedRoot $relativeSource)) }
  if (!(Test-BuildSamePath -Left $sourcePath -Right $resolvedRoot) -and
      !$sourcePath.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package asset Source escapes its configured $rootName root: '$relativeSource'."
  }
  $item = Get-Item -LiteralPath $resolvedRoot -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { throw "$($Variant.VariantKey) package asset does not exist: $sourcePath" }
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and $effectiveRootName -cne 'Staging') {
    throw "Package asset root is a reparse point outside the configured Staging root: $($item.FullName)"
  }
  if ($relativeSource -cne '.') {
    $currentPath = $resolvedRoot
    foreach ($segment in $segments) {
      $currentPath = Join-Path $currentPath $segment
      $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
      if ($null -eq $item) { throw "$($Variant.VariantKey) package asset does not exist: $sourcePath" }
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Package asset Source contains a nested reparse point, which is not supported: $($item.FullName)"
      }
    }
  }
  return [pscustomobject]@{ Root = $effectiveRootName; Item = $item }
}

function Get-BuildPackageDirectoryFiles {
  param(
    [Parameter(Mandatory = $true)][IO.DirectoryInfo]$Directory,
    [switch]$AllowRootReparsePoint
  )

  if (($Directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and !$AllowRootReparsePoint) {
    throw "Package asset directory is a reparse point outside the configured Staging root: $($Directory.FullName)"
  }
  $pending = [Collections.Generic.Stack[string]]::new()
  $files = [Collections.Generic.List[string]]::new()
  $pending.Push($Directory.FullName)
  while ($pending.Count -ne 0) {
    $current = $pending.Pop()
    foreach ($entryPath in [IO.Directory]::EnumerateFileSystemEntries($current, '*', [IO.SearchOption]::TopDirectoryOnly)) {
      $entry = Get-Item -LiteralPath $entryPath -Force
      if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Package asset directory contains a nested reparse point, which is not supported: $($entry.FullName)"
      }
      if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
      else { $files.Add($entry.FullName) }
    }
  }
  return @($files | Sort-Object)
}

function New-BuildPackagePayload {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $extension = [IO.Path]::GetExtension($Source).ToLowerInvariant()
  $resolvedSource = switch ($extension) {
    '.pex' { Assert-BuildPapyrusFile -Path $Source -Description $Description }
    '.swf' { Assert-BuildScaleformFile -Path $Source -Description $Description }
    '.gfx' { Assert-BuildScaleformFile -Path $Source -Description $Description }
    default { Resolve-BuildRequiredFile -Path $Source -Description $Description }
  }
  return [pscustomobject]@{
    Source = $resolvedSource
    Target = $Target.Replace('/', '\')
    ExpectedSha256 = Get-BuildFileSha256 -Path $resolvedSource
  }
}

function Test-BuildArchivePayloadIncluded {
  param(
    [Parameter(Mandatory = $true)][object]$Archive,
    [Parameter(Mandatory = $true)][string]$Target
  )

  # Archive2 filter expressions use Windows archive paths even when source-only checks run on another host.
  $candidate = '\' + $Target.Replace('/', '\')
  try {
    $includeFilters = [string](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'IncludeFilters' -DefaultValue '')
    if (![string]::IsNullOrWhiteSpace($includeFilters) -and ![regex]::IsMatch($candidate, $includeFilters, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
      return $false
    }
    $excludeFilters = [string](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'ExcludeFilters' -DefaultValue '')
    if (![string]::IsNullOrWhiteSpace($excludeFilters) -and [regex]::IsMatch($candidate, $excludeFilters, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
      return $false
    }
  }
  catch [ArgumentException] {
    throw "Archive payload filter is not a valid regular expression: $($_.Exception.Message)"
  }
  return $true
}

function Assert-BuildScaleformArchiveOwnership {
  param([Parameter(Mandatory = $true)][object]$Variant)

  foreach ($archive in @($Variant.Archives)) {
    $ownership = [string](Get-BuildPackagePropertyValue -InputObject $archive -Name 'ScaleformOwnership')
    if ([string]::IsNullOrWhiteSpace($ownership)) { continue }
    if ($ownership -cnotin @('Host', 'Consumer')) {
      throw "$($Variant.VariantKey) archive has unsupported ScaleformOwnership '$ownership'. Expected 'Host' or 'Consumer'."
    }

    $assets = @((Get-BuildPackagePropertyValue -InputObject $archive -Name 'Assets' -DefaultValue @()))
    $scaleformAssets = @($assets | Where-Object { [string](Get-BuildPackagePropertyValue -InputObject $_ -Name 'Root') -ieq 'Scaleform' })
    $classifiedAssets = @($assets | Where-Object {
      ![string]::IsNullOrWhiteSpace([string](Get-BuildPackagePropertyValue -InputObject $_ -Name 'ConsumerNamespace')) -or
      ![string]::IsNullOrWhiteSpace([string](Get-BuildPackagePropertyValue -InputObject $_ -Name 'DisplayMode'))
    })
    if ($ownership -ceq 'Host') {
      if ($classifiedAssets.Count -ne 0) {
        throw "$($Variant.VariantKey) host archive cannot declare consumer Scaleform asset metadata."
      }
      continue
    }
    if ($scaleformAssets.Count -eq 0) {
      throw "$($Variant.VariantKey) consumer archive must declare at least one Scaleform asset pair."
    }
    if ($classifiedAssets.Count -ne $scaleformAssets.Count) {
      throw "$($Variant.VariantKey) consumer archive must classify every Scaleform asset with ConsumerNamespace and DisplayMode."
    }

    $pairs = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($asset in $scaleformAssets) {
      $consumerNamespace = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'ConsumerNamespace')
      $displayMode = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'DisplayMode')
      $source = ([string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Source')).Replace('\', '/')
      $target = ([string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Target')).Replace('\', '/')
      if (![regex]::IsMatch($consumerNamespace, '\A[a-z0-9][a-z0-9.-]{1,62}[a-z0-9]\z', [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
        throw "$($Variant.VariantKey) consumer archive has invalid ConsumerNamespace '$consumerNamespace'."
      }
      if ($displayMode -cnotin @('normal', 'large')) {
        throw "$($Variant.VariantKey) consumer archive has unsupported DisplayMode '$displayMode'. Expected 'normal' or 'large'."
      }
      if ([string]::IsNullOrWhiteSpace($source)) {
        throw "$($Variant.VariantKey) consumer archive has an empty Scaleform Source."
      }
      $expectedTarget = "Interface/VenworksCanvas/Consumers/$consumerNamespace/$displayMode.swf"
      if ($target -cne $expectedTarget) {
        throw "$($Variant.VariantKey) consumer Scaleform target '$target' must be '$expectedTarget'."
      }
      if (!$pairs.ContainsKey($consumerNamespace)) {
        $pairs.Add($consumerNamespace, [pscustomobject]@{
          Source = $source
          Modes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        })
      }
      $pair = $pairs[$consumerNamespace]
      if ([string]$pair.Source -cne $source) {
        throw "$($Variant.VariantKey) consumer '$consumerNamespace' normal and large assets must use the same Scaleform Source."
      }
      if (!$pair.Modes.Add($displayMode)) {
        throw "$($Variant.VariantKey) consumer '$consumerNamespace' declares DisplayMode '$displayMode' more than once."
      }
    }
    foreach ($consumerNamespace in $pairs.Keys) {
      $modes = $pairs[$consumerNamespace].Modes
      if ($modes.Count -ne 2 -or !$modes.Contains('normal') -or !$modes.Contains('large')) {
        throw "$($Variant.VariantKey) consumer '$consumerNamespace' must declare one normal and one large Scaleform asset from the same source."
      }
    }
  }
}

function Assert-BuildConsumerScaleformPayloadOwnership {
  param(
    [Parameter(Mandatory = $true)][object]$Variant,
    [Parameter(Mandatory = $true)][object]$Archive,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Payloads
  )

  $ownership = [string](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'ScaleformOwnership')
  if ($ownership -cne 'Consumer') { return }
  $allowedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($asset in @((Get-BuildPackagePropertyValue -InputObject $Archive -Name 'Assets' -DefaultValue @()))) {
    if ([string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Root') -ine 'Scaleform') { continue }
    [void]$allowedTargets.Add(([string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Target')).Replace('\', '/'))
  }
  foreach ($payload in @($Payloads)) {
    $target = ([string]$payload.Target).Replace('\', '/')
    if ([IO.Path]::GetExtension($target).ToLowerInvariant() -notin @('.swf', '.gfx')) { continue }
    if (!$allowedTargets.Contains($target)) {
      throw "$($Variant.VariantKey) consumer archive cannot include undeclared Scaleform movie target '$target'."
    }
  }
}

function Get-BuildScaleformStagingPlans {
  param(
    [Parameter(Mandatory = $true)][object[]]$Variants,
    [Parameter(Mandatory = $true)][object[]]$Results
  )

  $variantsByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($variant in @($Variants)) {
    Assert-BuildScaleformArchiveOwnership -Variant $variant
    $variantKey = [string]$variant.VariantKey
    if ([string]::IsNullOrWhiteSpace($variantKey) -or $variantsByKey.ContainsKey($variantKey)) {
      throw "Scaleform staging requires unique, non-empty selected variant keys."
    }
    $variantsByKey.Add($variantKey, $variant)
  }

  $resultsByKey = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($result in @($Results)) {
    $variantKey = [string]$result.VariantKey
    $outputSet = [string]$result.OutputSet
    $outputFile = [string]$result.OutputFile
    if (!$variantsByKey.ContainsKey($variantKey)) {
      throw "Scaleform result '$outputSet/$outputFile' belongs to an unselected or unknown variant '$variantKey'."
    }
    $relativeSource = "$($outputSet.Replace('\', '/').TrimEnd('/'))/$($outputFile.Replace('\', '/').TrimStart('/'))"
    $resultKey = "$variantKey`n$relativeSource"
    if ($resultsByKey.ContainsKey($resultKey)) {
      throw "Scaleform result '$relativeSource' is ambiguous for selected variant '$variantKey'."
    }
    $resultsByKey.Add($resultKey, $result)
  }

  $plans = [Collections.Generic.List[object]]::new()
  $mappedResultKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $targetsByKey = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($variant in @($Variants)) {
    $variantKey = [string]$variant.VariantKey
    foreach ($archive in @($variant.Archives)) {
      foreach ($asset in @((Get-BuildPackagePropertyValue -InputObject $archive -Name 'Assets' -DefaultValue @()))) {
        if ([string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Root') -ine 'Scaleform') { continue }
        $relativeSource = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Source')
        if ([string]::IsNullOrWhiteSpace($relativeSource) -or [IO.Path]::IsPathRooted($relativeSource) -or $relativeSource.Contains(':')) {
          throw "Scaleform staging Source must be a non-rooted relative file path: '$relativeSource'."
        }
        $sourceSegments = $relativeSource.Split([char[]]@('\', '/'), [StringSplitOptions]::None)
        if (@($sourceSegments | Where-Object { [string]::IsNullOrEmpty($_) -or $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0) {
          throw "Scaleform staging Source contains an empty or traversal segment: '$relativeSource'."
        }
        $normalizedSource = $relativeSource.Replace('\', '/')
        $resultKey = "$variantKey`n$normalizedSource"
        if (!$resultsByKey.ContainsKey($resultKey)) {
          throw "Scaleform staging mapping '$normalizedSource' does not match a selected output for variant '$variantKey'."
        }

        $target = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Target' -DefaultValue '')
        $destinationPath = Resolve-BuildArchiveTarget -Root ([string]$variant.StagingFolderPath) -Target $target
        $normalizedTarget = $target.Replace('\', '/')
        $targetKey = "$variantKey`n$normalizedTarget"
        if ($targetsByKey.ContainsKey($targetKey)) {
          if (![string]::Equals($targetsByKey[$targetKey], $normalizedSource, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Scaleform staging target '$normalizedTarget' is ambiguously mapped for variant '$variantKey'."
          }
          continue
        }
        $targetsByKey.Add($targetKey, $normalizedSource)
        [void]$mappedResultKeys.Add($resultKey)
        $plans.Add([pscustomobject]@{
          VariantKey = $variantKey
          Variant = $variant
          Source = $normalizedSource
          Target = $normalizedTarget
          CandidatePath = [string]$resultsByKey[$resultKey].Path
          DestinationPath = $destinationPath
        })
      }
    }
  }

  foreach ($resultKey in $resultsByKey.Keys) {
    if (!$mappedResultKeys.Contains($resultKey)) {
      $result = $resultsByKey[$resultKey]
      throw "Scaleform output '$($result.OutputSet)/$($result.OutputFile)' does not have a staging target mapping for variant '$($result.VariantKey)'."
    }
  }
  return @($plans)
}

function Get-BuildPackageArchivePlans {
  param(
    [Parameter(Mandatory = $true)][object[]]$Variants,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$PapyrusSourceRoot,
    [AllowEmptyString()][string]$ScriptsDirectory,
    [AllowEmptyString()][string]$ScaleformDirectory
  )

  $plans = [Collections.Generic.List[object]]::new()
  foreach ($variant in @($Variants)) {
    Assert-BuildScaleformArchiveOwnership -Variant $variant
    $archiveNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($archive in @($variant.Archives)) {
      $fileName = [string](Get-BuildPackagePropertyValue -InputObject $archive -Name 'FileName')
      Assert-BuildPackageLeafName -Name $fileName -Extension '.ba2' -Description "$($variant.VariantKey) archive FileName"
      if (!$archiveNames.Add($fileName)) { throw "$($variant.VariantKey) configures archive filename '$fileName' more than once." }
      $format = [string](Get-BuildPackagePropertyValue -InputObject $archive -Name 'Format')
      $compression = [string](Get-BuildPackagePropertyValue -InputObject $archive -Name 'Compression')
      $maxSizeMB = [int](Get-BuildPackagePropertyValue -InputObject $archive -Name 'MaxSizeMB' -DefaultValue 2048)
      if ([string]::IsNullOrWhiteSpace($format) -or [string]::IsNullOrWhiteSpace($compression) -or $maxSizeMB -le 0) {
        throw "$($variant.VariantKey) archive '$fileName' requires Format, Compression, and a positive MaxSizeMB."
      }

      $includePapyrus = [bool](Get-BuildPackagePropertyValue -InputObject $archive -Name 'IncludePapyrus' -DefaultValue $false)
      $payloads = [Collections.Generic.List[object]]::new()
      foreach ($asset in @((Get-BuildPackagePropertyValue -InputObject $archive -Name 'Assets' -DefaultValue @()))) {
        $resolved = Resolve-BuildPackageAssetSource -Asset $asset -Variant $variant -RepositoryRoot $RepositoryRoot -ScaleformDirectory $ScaleformDirectory
        $target = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Target' -DefaultValue '')
        if ($resolved.Item.PSIsContainer) {
          [void](Resolve-BuildArchiveTarget -Root $resolved.Item.FullName -Target $target -AllowRoot)
          $relativeSource = [string](Get-BuildPackagePropertyValue -InputObject $asset -Name 'Source')
          $allowRootReparsePoint = $resolved.Root -ceq 'Staging' -and $relativeSource -ceq '.'
          foreach ($file in @(Get-BuildPackageDirectoryFiles -Directory $resolved.Item -AllowRootReparsePoint:$allowRootReparsePoint)) {
            $relative = [IO.Path]::GetRelativePath($resolved.Item.FullName, $file)
            $archiveTarget = if ([string]::IsNullOrWhiteSpace($target)) { $relative } else { Join-Path $target $relative }
            $normalizedTarget = $archiveTarget.Replace('\', '/')
            if ($includePapyrus -and $resolved.Root -ceq 'Staging' -and
                ($normalizedTarget -ieq 'Scripts' -or $normalizedTarget.StartsWith('Scripts/', [StringComparison]::OrdinalIgnoreCase))) {
              continue
            }
            if (!(Test-BuildArchivePayloadIncluded -Archive $archive -Target $archiveTarget)) { continue }
            $payloads.Add((New-BuildPackagePayload -Source $file -Target $archiveTarget -Description "$($variant.VariantKey) archive payload '$archiveTarget'"))
          }
        }
        else {
          if (($resolved.Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Package asset file is a reparse point outside its declared root: $($resolved.Item.FullName)"
          }
          [void](Resolve-BuildArchiveTarget -Root $RepositoryRoot -Target $target)
          if (!(Test-BuildArchivePayloadIncluded -Archive $archive -Target $target)) { continue }
          $payloads.Add((New-BuildPackagePayload -Source $resolved.Item.FullName -Target $target -Description "$($variant.VariantKey) archive payload '$target'"))
        }
      }

      if ($includePapyrus) {
        $variantScriptsDirectory = if ([string]::IsNullOrWhiteSpace($ScriptsDirectory)) {
          Join-Path ([string]$variant.StagingFolderPath) 'Scripts'
        }
        else { $ScriptsDirectory }
        foreach ($script in @(Get-BuildPapyrusSources -Variant $variant -SourceRoot $PapyrusSourceRoot)) {
          $relativeOutput = [string]$script.RelativeOutput
          $compiledPath = Join-Path $variantScriptsDirectory $relativeOutput
          $archiveTarget = Join-Path 'Scripts' $relativeOutput
          if (!(Test-BuildArchivePayloadIncluded -Archive $archive -Target $archiveTarget)) { continue }
          $payloads.Add((New-BuildPackagePayload -Source $compiledPath -Target $archiveTarget -Description "$($variant.VariantKey) compiled Papyrus payload '$archiveTarget'"))
        }
      }

      Assert-BuildConsumerScaleformPayloadOwnership -Variant $variant -Archive $archive -Payloads @($payloads)
      $targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      foreach ($payload in @($payloads)) {
        [void](Resolve-BuildArchiveTarget -Root $RepositoryRoot -Target ([string]$payload.Target))
        $normalizedTarget = ([string]$payload.Target).Replace('/', '\')
        if (!$targets.Add($normalizedTarget)) { throw "$($variant.VariantKey) archive '$fileName' maps more than one payload to '$normalizedTarget'." }
      }
      $plans.Add([pscustomobject]@{
        VariantKey = [string]$variant.VariantKey
        Variant = $variant
        Archive = $archive
        FileName = $fileName
        Payloads = @($payloads)
      })
    }
  }
  return @($plans)
}

function Get-BuildPackageInstallOperations {
  param(
    [Parameter(Mandatory = $true)][object[]]$SelectedVariants,
    [Parameter(Mandatory = $true)][object[]]$AllVariants
  )

  $operations = [Collections.Generic.List[object]]::new()
  foreach ($stagingOperation in @(Get-BuildStagingOperations -SelectedVariants $SelectedVariants -AllVariants $AllVariants)) {
    $variant = $stagingOperation.Variant
    $key = [string]$stagingOperation.Key
    $stagingPath = [string]$stagingOperation.StagingPath
    $targetPath = [string]$stagingOperation.InstallPath
    $pluginName = [string]$variant.EsmFileName
    Assert-BuildPackageLeafName -Name $pluginName -Extension '.esm' -Description "$key EsmFileName"
    $archiveNames = @($variant.Archives | ForEach-Object {
      $name = [string](Get-BuildPackagePropertyValue -InputObject $_ -Name 'FileName')
      Assert-BuildPackageLeafName -Name $name -Extension '.ba2' -Description "$key archive FileName"
      $name
    })
    if (@($archiveNames | Select-Object -Unique).Count -ne $archiveNames.Count) { throw "$key archive filenames must be unique." }
    $managedNames = @($pluginName) + $archiveNames
    foreach ($managedName in $managedNames) {
      $managedItem = Get-Item -LiteralPath (Join-Path $targetPath $managedName) -Force -ErrorAction SilentlyContinue
      if ($null -ne $managedItem -and $managedItem.PSIsContainer) { throw "$key managed package path is a directory: $($managedItem.FullName)" }
    }
    $pluginPath = Resolve-BuildRequiredFile -Path (Join-Path $targetPath $pluginName) -Description "$key live staging ESM"
    Assert-BuildArtifactHeader -Path $pluginPath
    foreach ($archiveName in $archiveNames) {
      $archivePath = Join-Path $targetPath $archiveName
      if (Test-Path -LiteralPath $archivePath -PathType Leaf) { Assert-BuildArtifactHeader -Path $archivePath }
    }
    $operations.Add([pscustomobject]@{
      Key = $key
      Variant = $variant
      StagingPath = $stagingPath
      InstallPath = $targetPath
      PluginName = $pluginName
      ArchiveNames = $archiveNames
      SourcePluginPath = $pluginPath
      ManagedNames = $managedNames
      CandidateNames = @($managedNames)
    })
  }
  return @($operations)
}

function Enter-BuildPackageLock {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$TransactionId
  )

  $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  try {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  }
  catch [IO.IOException] {
    throw "Another package process owns the exclusive package lock: $Path"
  }
  try {
    $content = [Text.UTF8Encoding]::new($false).GetBytes("VENWORKS_PACKAGE_LOCK/1`nTransaction=$TransactionId`nProcess=$PID`n")
    $stream.SetLength(0)
    $stream.Write($content, 0, $content.Length)
    $stream.Flush($true)
    return $stream
  }
  catch {
    $stream.Dispose()
    throw
  }
}

function Assert-BuildNoIncompletePackageTransactions {
  param([Parameter(Mandatory = $true)][string]$TransactionBase)

  $base = [IO.Path]::GetFullPath($TransactionBase)
  if (!(Test-Path -LiteralPath $base -PathType Container)) { return }
  $retained = @(Get-ChildItem -LiteralPath $base -Directory -Force)
  if ($retained.Count -eq 0) { return }
  $descriptions = @($retained | ForEach-Object {
    $journalPath = Join-Path $_.FullName 'transaction.json'
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
      try {
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        "$($_.Name) [$($journal.Status)]"
      }
      catch { "$($_.Name) [unreadable journal]" }
    }
    else { "$($_.Name) [missing journal]" }
  })
  throw "Retained package transaction directories require manual inspection before packaging: $([string]::Join(', ', $descriptions))"
}

function Write-BuildPackageTransactionJournal {
  param(
    [Parameter(Mandatory = $true)][string]$TransactionPath,
    [Parameter(Mandatory = $true)][string]$TransactionId,
    [Parameter(Mandatory = $true)][string]$Status,
    [Parameter(Mandatory = $true)][string[]]$VariantKeys,
    [string]$Failure
  )

  $journal = [ordered]@{
    Schema = 'VENWORKS_PACKAGE_TRANSACTION/1'
    TransactionId = $TransactionId
    ProcessId = $PID
    Status = $Status
    Variants = @($VariantKeys)
    Failure = if ([string]::IsNullOrWhiteSpace($Failure)) { $null } else { $Failure }
  }
  Write-BuildUtf8WithoutBom -Path (Join-Path $TransactionPath 'transaction.json') -Text (($journal | ConvertTo-Json -Depth 5) + "`n")
}

function Copy-BuildVerifiedFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Description
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination
  if ((Get-BuildFileSha256 -Path $Source) -cne $ExpectedSha256 -or (Get-BuildFileSha256 -Path $Destination) -cne $ExpectedSha256) {
    throw "$Description changed while it was copied."
  }
}

function Install-BuildVerifiedFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $temporaryPath = "$Destination.$PID-$([guid]::NewGuid().ToString('N')).new"
  try {
    Copy-BuildVerifiedFile -Source $Source -Destination $temporaryPath -ExpectedSha256 $ExpectedSha256 -Description $Description
    [IO.File]::Move($temporaryPath, $Destination, $true)
    if ((Get-BuildFileSha256 -Path $Destination) -cne $ExpectedSha256) { throw "$Description differs after installation." }
  }
  finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
  }
}

function Restore-BuildPackageOperation {
  param([Parameter(Mandatory = $true)][object]$Operation)

  Assert-BuildJunctionTarget -StagingPath $Operation.StagingPath -ExpectedTargetPath $Operation.InstallPath
  $backupItems = @(Get-ChildItem -LiteralPath $Operation.BackupPath -File -Force)
  Assert-BuildExactNames -Actual @($backupItems.Name) -Expected @($Operation.OriginalNames) -Description "$($Operation.Key) recovery backup inventory"
  foreach ($name in @($Operation.OriginalNames)) {
    $backupPath = Resolve-BuildRequiredFile -Path (Join-Path $Operation.BackupPath $name) -Description "$($Operation.Key) recovery file '$name'"
    if (!$Operation.OriginalHashes.ContainsKey($name) -or (Get-BuildFileSha256 -Path $backupPath) -cne [string]$Operation.OriginalHashes[$name]) {
      throw "$($Operation.Key) recovery backup failed preflight for '$name'."
    }
  }
  foreach ($name in @($Operation.CandidateNames)) {
    $installedPath = Join-Path $Operation.InstallPath $name
    if (Test-Path -LiteralPath $installedPath -PathType Leaf) { Remove-Item -LiteralPath $installedPath -Force }
  }
  foreach ($name in @($Operation.OriginalNames)) {
    $backupPath = Join-Path $Operation.BackupPath $name
    $destination = Join-Path $Operation.InstallPath $name
    $expectedHash = [string]$Operation.OriginalHashes[$name]
    $temporaryPath = "$destination.$PID-$([guid]::NewGuid().ToString('N')).restore"
    try {
      Copy-Item -LiteralPath $backupPath -Destination $temporaryPath
      if ((Get-BuildFileSha256 -Path $temporaryPath) -cne $expectedHash) { throw "$($Operation.Key) recovery copy differs for '$name'." }
      [IO.File]::Move($temporaryPath, $destination, $true)
      if ((Get-BuildFileSha256 -Path $destination) -cne $expectedHash) { throw "$($Operation.Key) restored file differs for '$name'." }
    }
    finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
  }
}

function Assert-BuildInstalledPackage {
  param(
    [Parameter(Mandatory = $true)][object]$Variant,
    [Parameter(Mandatory = $true)][string]$InstallPath
  )

  $key = [string]$Variant.VariantKey
  $directory = Resolve-BuildRequiredDirectory -Path $InstallPath -Description "$key installed package directory"
  $managedNames = @([string]$Variant.EsmFileName) + @($Variant.Archives | ForEach-Object { [string](Get-BuildPackagePropertyValue -InputObject $_ -Name 'FileName') })
  foreach ($name in $managedNames) {
    $path = Resolve-BuildRequiredFile -Path (Join-Path $directory $name) -Description "$key installed package file '$name'"
    Assert-BuildArtifactHeader -Path $path
  }
}

function Get-BuildArchive2Arguments {
  param(
    [Parameter(Mandatory = $true)][object]$Archive,
    [Parameter(Mandatory = $true)][string]$ArchiveRoot,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )

  $rootWithSeparator = (Get-BuildNormalizedFullPath -Path $ArchiveRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $arguments = [Collections.Generic.List[string]]::new()
  $arguments.Add($rootWithSeparator)
  $arguments.Add("-root=$rootWithSeparator")
  $arguments.Add("-create=$OutputPath")
  $arguments.Add("-format=$([string](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'Format'))")
  $arguments.Add("-compression=$([string](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'Compression'))")
  $arguments.Add("-maxSizeMB=$([int](Get-BuildPackagePropertyValue -InputObject $Archive -Name 'MaxSizeMB' -DefaultValue 2048))")
  foreach ($filterName in @('IncludeFilters', 'ExcludeFilters')) {
    $filterValue = [string](Get-BuildPackagePropertyValue -InputObject $Archive -Name $filterName -DefaultValue '')
    if (![string]::IsNullOrWhiteSpace($filterValue)) {
      $arguments.Add("-$($filterName.Substring(0, 1).ToLowerInvariant())$($filterName.Substring(1))=$filterValue")
    }
  }
  return @($arguments)
}

function Invoke-BuildArchive2 {
  param(
    [Parameter(Mandatory = $true)][string]$Archive2Path,
    [Parameter(Mandatory = $true)][object]$Archive,
    [Parameter(Mandatory = $true)][string]$ArchiveRoot,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $arguments = @(Get-BuildArchive2Arguments -Archive $Archive -ArchiveRoot $ArchiveRoot -OutputPath $OutputPath)
  $oldNativePreference = $PSNativeCommandUseErrorActionPreference
  try {
    $PSNativeCommandUseErrorActionPreference = $false
    & $Archive2Path @arguments
    $exitCode = $LASTEXITCODE
  }
  finally {
    $PSNativeCommandUseErrorActionPreference = $oldNativePreference
  }
  if ($exitCode -ne 0) { throw "Archive2 failed to build $Description with exit code $exitCode." }
  $archivePath = Resolve-BuildRequiredFile -Path $OutputPath -Description "$Description output"
  Assert-BuildArtifactHeader -Path $archivePath
  return $archivePath
}
