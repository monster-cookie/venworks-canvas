$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

class ModuleVariant {
  [string]$VariantKey
  [string]$VariantName
  [string]$EsmFileName
  [string]$PackageBaseName
  [string]$PapyrusNamespace
  [string]$StagingFolderPath
  [string]$EnvironmentVariableName
  [object[]]$ScaleformBuilds
  [object[]]$Archives

  ModuleVariant(
    [string]$variantKey,
    [string]$variantName,
    [string]$esmFileName,
    [string]$packageBaseName,
    [string]$papyrusNamespace,
    [string]$stagingFolderPath,
    [string]$environmentVariableName,
    [object[]]$scaleformBuilds,
    [object[]]$archives
  ) {
    $this.VariantKey = $variantKey
    $this.VariantName = $variantName
    $this.EsmFileName = $esmFileName
    $this.PackageBaseName = $packageBaseName
    $this.PapyrusNamespace = $papyrusNamespace
    $this.StagingFolderPath = $stagingFolderPath
    $this.EnvironmentVariableName = $environmentVariableName
    $this.ScaleformBuilds = $scaleformBuilds
    $this.Archives = $archives
  }
}

function Global:Get-ModuleVariants {
  [CmdletBinding()]
  param(
    [Alias('VariantKey')]
    [string[]]$VariantKeys
  )

  $moduleVariantsVariable = Get-Variable -Name ModuleVariants -Scope Global -ErrorAction SilentlyContinue
  if ($null -eq $moduleVariantsVariable) {
    throw 'ModuleVariants must be configured before selecting variants.'
  }
  $configuredVariants = @($moduleVariantsVariable.Value)
  $configuredKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $configuredNamespaces = [Collections.Generic.List[object]]::new()
  foreach ($variant in $configuredVariants) {
    $key = [string]$variant.VariantKey
    if ([string]::IsNullOrWhiteSpace($key)) {
      throw 'Configured module variant keys cannot be empty.'
    }
    $normalizedKey = $key.Trim()
    if (!$configuredKeys.Add($normalizedKey)) {
      throw "Configured module variant key '$key' is repeated."
    }

    $namespace = [string]$variant.PapyrusNamespace
    $namespaceSegments = @($namespace.Split(':'))
    if ([string]::IsNullOrWhiteSpace($namespace) -or
        $namespaceSegments.Count -eq 0 -or
        @($namespaceSegments | Where-Object { $_ -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' }).Count -ne 0) {
      throw "Module variant '$normalizedKey' has invalid Papyrus namespace '$namespace'."
    }
    foreach ($configuredNamespace in $configuredNamespaces) {
      $otherNamespace = [string]$configuredNamespace.Namespace
      if ([string]::Equals($namespace, $otherNamespace, [StringComparison]::OrdinalIgnoreCase) -or
          $namespace.StartsWith($otherNamespace + ':', [StringComparison]::OrdinalIgnoreCase) -or
          $otherNamespace.StartsWith($namespace + ':', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Configured Papyrus namespaces '$otherNamespace' ($($configuredNamespace.VariantKey)) and '$namespace' ($normalizedKey) overlap."
      }
    }
    $configuredNamespaces.Add([pscustomobject]@{
      VariantKey = $normalizedKey
      Namespace = $namespace
    })
  }

  if ($null -eq $VariantKeys -or $VariantKeys.Count -eq 0) {
    return @($configuredVariants)
  }

  $requestedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $normalizedKeys = @($VariantKeys | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) {
      throw 'Variant keys cannot be empty.'
    }
    $normalizedRequestedKey = $_.Trim()
    if (!$requestedKeys.Add($normalizedRequestedKey)) {
      throw 'Variant keys cannot be repeated.'
    }
    $normalizedRequestedKey
  })

  $selectedVariants = foreach ($normalizedRequestedKey in $normalizedKeys) {
    $matchingVariants = @($configuredVariants | Where-Object {
      [string]::Equals(([string]$_.VariantKey).Trim(), $normalizedRequestedKey, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($matchingVariants.Count -ne 1) {
      throw "Unknown module variant key '$normalizedRequestedKey'."
    }
    $matchingVariants[0]
  }
  return @($selectedVariants)
}
