$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-BuildScaleformValue {
  param(
    [Parameter(Mandatory = $true)][object]$InputObject,
    [Parameter(Mandatory = $true)][string]$Name,
    [switch]$Required,
    [string]$Description = 'Scaleform configuration'
  )

  $found = $false
  $value = $null
  if ($InputObject -is [System.Collections.IDictionary]) {
    if ($InputObject.Contains($Name)) {
      $found = $true
      $value = $InputObject[$Name]
    }
  }
  else {
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
      $found = $true
      $value = $property.Value
    }
  }

  if ($Required -and (!$found -or $null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)))) {
    throw "$Description must declare '$Name'."
  }
  return $value
}

function Assert-BuildScaleformRelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$AllowDirectory
  )

  if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) {
    throw "$Description must be a non-rooted relative path: '$Path'."
  }
  $segments = @($Path -split '[\\/]' | ForEach-Object { [string]$_ })
  if ($segments.Count -eq 0 -or @($segments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -in @('.', '..') }).Count -ne 0) {
    throw "$Description contains an empty or traversal segment: '$Path'."
  }
  if (!$AllowDirectory -and $segments.Count -ne 1) {
    throw "$Description must be a file name without directories: '$Path'."
  }
  return [string]::Join([System.IO.Path]::DirectorySeparatorChar, $segments)
}

function Resolve-BuildScaleformConfigurationFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepositoryRoot $Path }
  return Resolve-BuildRequiredFile -Path $candidate -Description $Description
}

function ConvertTo-BuildScaleformJobs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Variants,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot
  )

  $resolvedRepositoryRoot = Resolve-BuildRequiredDirectory -Path $RepositoryRoot -Description 'Repository root'
  $jobs = [System.Collections.Generic.List[object]]::new()
  $jobNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $outputKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $patchOutputSets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  $outputSetKinds = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($variant in @($Variants)) {
    $variantKey = [string](Get-BuildScaleformValue -InputObject $variant -Name 'VariantKey' -Required -Description 'Module variant')
    $configuredJobs = @(Get-BuildScaleformValue -InputObject $variant -Name 'ScaleformBuilds' -Description "Module variant '$variantKey'")
    foreach ($configuredJob in $configuredJobs) {
      if ($null -eq $configuredJob) {
        throw "Module variant '$variantKey' contains an empty Scaleform build job."
      }
      $description = "Scaleform build job for variant '$variantKey'"
      $name = [string](Get-BuildScaleformValue -InputObject $configuredJob -Name 'Name' -Required -Description $description)
      if (!$jobNames.Add($name)) {
        throw "Scaleform build job name '$name' is repeated in the selected variants."
      }
      $kindValue = [string](Get-BuildScaleformValue -InputObject $configuredJob -Name 'Kind' -Required -Description $description)
      $kind = switch ($kindValue.ToUpperInvariant()) {
        'FLEX' { 'Flex' }
        'PATCH' { 'Patch' }
        default { throw "Scaleform build job '$name' has unsupported kind '$kindValue'." }
      }
      $outputSet = Assert-BuildScaleformRelativePath -Path ([string](Get-BuildScaleformValue -InputObject $configuredJob -Name 'OutputSet' -Required -Description $description)) -Description "Scaleform build job '$name' output set" -AllowDirectory
      if ($outputSetKinds.ContainsKey($outputSet) -and $outputSetKinds[$outputSet] -cne $kind) {
        throw "Scaleform output set '$outputSet' mixes '$($outputSetKinds[$outputSet])' and '$kind' publication behavior."
      }
      $outputSetKinds[$outputSet] = $kind
      if ($kind -ceq 'Patch' -and !$patchOutputSets.Add($outputSet)) {
        throw "Patched Scaleform output set '$outputSet' is declared by more than one selected job."
      }

      $configuredOutputs = @(Get-BuildScaleformValue -InputObject $configuredJob -Name 'Outputs' -Required -Description $description)
      if ($configuredOutputs.Count -eq 0) {
        throw "Scaleform build job '$name' must declare at least one output."
      }
      if ($kind -ceq 'Flex' -and $configuredOutputs.Count -ne 1) {
        throw "Flex Scaleform build job '$name' must declare exactly one output."
      }

      $outputs = [System.Collections.Generic.List[object]]::new()
      foreach ($configuredOutput in $configuredOutputs) {
        if ($null -eq $configuredOutput) {
          throw "Scaleform build job '$name' contains an empty output."
        }
        $outputFile = Assert-BuildScaleformRelativePath -Path ([string](Get-BuildScaleformValue -InputObject $configuredOutput -Name 'OutputFile' -Required -Description "Scaleform build job '$name' output")) -Description "Scaleform build job '$name' output file"
        $outputKey = "$outputSet/$outputFile"
        if (!$outputKeys.Add($outputKey)) {
          throw "Scaleform output '$outputKey' is declared more than once in the selected variants."
        }
        $inputFile = $null
        $displayMode = $null
        if ($kind -ceq 'Patch') {
          $inputFile = Assert-BuildScaleformRelativePath -Path ([string](Get-BuildScaleformValue -InputObject $configuredOutput -Name 'InputFile' -Required -Description "Scaleform build job '$name' output '$outputFile'")) -Description "Scaleform build job '$name' input file"
          $displayMode = [string](Get-BuildScaleformValue -InputObject $configuredOutput -Name 'DisplayMode' -Description "Scaleform build job '$name' output '$outputFile'")
        }
        $outputs.Add([pscustomobject]@{
          InputFile = $inputFile
          OutputFile = $outputFile
          DisplayMode = $displayMode
        })
      }

      $manifestPath = $null
      $patchPath = $null
      if ($kind -ceq 'Flex') {
        $manifestPath = Resolve-BuildScaleformConfigurationFile `
          -Path ([string](Get-BuildScaleformValue -InputObject $configuredJob -Name 'ManifestPath' -Required -Description $description)) `
          -RepositoryRoot $resolvedRepositoryRoot `
          -Description "Scaleform movie manifest for job '$name'"
        $definition = Get-BuildScaleformMovieDefinition -ManifestPath $manifestPath
        if ([string]$definition.OutputFile -cne [string]$outputs[0].OutputFile) {
          throw "Scaleform job '$name' configures output '$($outputs[0].OutputFile)' but its manifest emits '$($definition.OutputFile)'."
        }
      }
      else {
        $patchPath = Resolve-BuildScaleformConfigurationFile `
          -Path ([string](Get-BuildScaleformValue -InputObject $configuredJob -Name 'PatchPath' -Required -Description $description)) `
          -RepositoryRoot $resolvedRepositoryRoot `
          -Description "ActionScript patch for job '$name'"
        foreach ($output in @($outputs)) {
          [void](Get-BuildActionScriptPatch -PatchPath $patchPath -DisplayMode ([string]$output.DisplayMode))
          if (![string]::IsNullOrWhiteSpace([string]$output.DisplayMode)) {
            $inputIsLarge = [regex]::IsMatch([string]$output.InputFile, '_lrg\.(swf|gfx)\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $outputIsLarge = [regex]::IsMatch([string]$output.OutputFile, '_lrg\.(swf|gfx)\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($inputIsLarge -ne $outputIsLarge) {
              throw "Scaleform job '$name' output '$($output.OutputFile)' mixes normal and large input/output filenames."
            }
            $expectedDisplayMode = if ($inputIsLarge) { 'large' } else { 'normal' }
            if ([string]$output.DisplayMode -cne $expectedDisplayMode) {
              throw "Scaleform job '$name' output '$($output.OutputFile)' must use DisplayMode '$expectedDisplayMode'."
            }
          }
        }
      }

      $jobs.Add([pscustomobject]@{
        Name = $name
        Kind = $kind
        OutputSet = $outputSet
        ManifestPath = $manifestPath
        PatchPath = $patchPath
        Outputs = @($outputs)
        VariantKey = $variantKey
      })
    }
  }

  $ownershipRoot = Join-Path $resolvedRepositoryRoot '.scaleform-output-ownership'
  for ($leftIndex = 0; $leftIndex -lt $jobs.Count; $leftIndex++) {
    $leftJob = $jobs[$leftIndex]
    $leftSetPath = Get-BuildNormalizedFullPath -Path (Join-Path $ownershipRoot ([string]$leftJob.OutputSet))
    for ($rightIndex = $leftIndex + 1; $rightIndex -lt $jobs.Count; $rightIndex++) {
      $rightJob = $jobs[$rightIndex]
      $rightSetPath = Get-BuildNormalizedFullPath -Path (Join-Path $ownershipRoot ([string]$rightJob.OutputSet))
      if (Test-BuildSamePath -Left $leftSetPath -Right $rightSetPath) {
        continue
      }

      $leftPrefix = $leftSetPath + [System.IO.Path]::DirectorySeparatorChar
      $rightPrefix = $rightSetPath + [System.IO.Path]::DirectorySeparatorChar
      $rightIsNested = $rightSetPath.StartsWith($leftPrefix, [System.StringComparison]::OrdinalIgnoreCase)
      $leftIsNested = $leftSetPath.StartsWith($rightPrefix, [System.StringComparison]::OrdinalIgnoreCase)
      if ($rightIsNested -and [string]$leftJob.Kind -ceq 'Patch') {
        throw "Patched Scaleform output set '$($leftJob.OutputSet)' owns a directory containing output set '$($rightJob.OutputSet)'."
      }
      if ($leftIsNested -and [string]$rightJob.Kind -ceq 'Patch') {
        throw "Patched Scaleform output set '$($rightJob.OutputSet)' owns a directory containing output set '$($leftJob.OutputSet)'."
      }

      if ([string]$leftJob.Kind -ceq 'Flex') {
        $leftOutputPath = Get-BuildNormalizedFullPath -Path (Join-Path $leftSetPath ([string]$leftJob.Outputs[0].OutputFile))
        if ((Test-BuildSamePath -Left $leftOutputPath -Right $rightSetPath) -or
            $rightSetPath.StartsWith(($leftOutputPath + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "Scaleform output '$($leftJob.OutputSet)/$($leftJob.Outputs[0].OutputFile)' conflicts with output-set directory '$($rightJob.OutputSet)'."
        }
      }
      if ([string]$rightJob.Kind -ceq 'Flex') {
        $rightOutputPath = Get-BuildNormalizedFullPath -Path (Join-Path $rightSetPath ([string]$rightJob.Outputs[0].OutputFile))
        if ((Test-BuildSamePath -Left $rightOutputPath -Right $leftSetPath) -or
            $leftSetPath.StartsWith(($rightOutputPath + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {
          throw "Scaleform output '$($rightJob.OutputSet)/$($rightJob.Outputs[0].OutputFile)' conflicts with output-set directory '$($leftJob.OutputSet)'."
        }
      }
    }
  }
  return @($jobs)
}

function Assert-BuildScaleformSourceTokens {
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

function Get-BuildActionScriptPatch {
  param(
    [Parameter(Mandatory = $true)][string]$PatchPath,
    [AllowEmptyString()][string]$DisplayMode
  )

  $resolvedPatchPath = Resolve-BuildRequiredFile -Path $PatchPath -Description 'ActionScript patch'
  [xml]$document = Get-Content -LiteralPath $resolvedPatchPath -Raw
  $patch = $document.actionScriptPatch
  if ($null -eq $patch) {
    throw "Invalid ActionScript patch: $resolvedPatchPath"
  }
  $insertions = @($patch.SelectNodes('insertions/insertion'))
  if ([string]::IsNullOrWhiteSpace([string]$patch.script) -or $insertions.Count -eq 0) {
    throw "Invalid ActionScript patch: $resolvedPatchPath"
  }
  $displayModeMarker = '__VWCANVAS_DISPLAY_MODE__'
  $parsedInsertions = @($insertions | ForEach-Object {
    [pscustomobject]@{
      Position = [string]$_.position
      Anchor = [string]$_.anchor.InnerText
      Content = [string]$_.content.InnerText
    }
  })
  $requiredSourceTokens = @($patch.SelectNodes('validation/requiredSourceTokens/token') | ForEach-Object { [string]$_.InnerText })
  $requiredInspectionTokens = @($patch.SelectNodes('validation/requiredInspectionTokens/token') | ForEach-Object { [string]$_.InnerText })
  if (([string]$patch.script).Contains($displayModeMarker) -or @($parsedInsertions | Where-Object { $_.Anchor.Contains($displayModeMarker) }).Count -ne 0) {
    throw "ActionScript patch '$resolvedPatchPath' uses the display-mode marker outside replaceable content."
  }
  $contentUsesDisplayMode = @($parsedInsertions | Where-Object { $_.Content.Contains($displayModeMarker) }).Count -ne 0
  $sourceValidationUsesDisplayMode = @($requiredSourceTokens | Where-Object { $_.Contains($displayModeMarker) }).Count -ne 0
  $inspectionUsesDisplayMode = @($requiredInspectionTokens | Where-Object { $_.Contains($displayModeMarker) }).Count -ne 0
  $usesDisplayMode = $contentUsesDisplayMode -or $sourceValidationUsesDisplayMode -or $inspectionUsesDisplayMode
  if ($usesDisplayMode) {
    if (!$contentUsesDisplayMode -or !$sourceValidationUsesDisplayMode -or !$inspectionUsesDisplayMode) {
      throw "ActionScript patch '$resolvedPatchPath' must use the display-mode marker in insertion content and required source and inspection tokens."
    }
    if ([string]::IsNullOrWhiteSpace($DisplayMode)) {
      throw "ActionScript patch '$resolvedPatchPath' requires DisplayMode 'normal' or 'large'."
    }
    if ($DisplayMode -cnotin @('normal', 'large')) {
      throw "ActionScript patch '$resolvedPatchPath' has unsupported DisplayMode '$DisplayMode'. Expected 'normal' or 'large'."
    }
    foreach ($insertion in $parsedInsertions) {
      $insertion.Content = $insertion.Content.Replace($displayModeMarker, $DisplayMode)
    }
    $requiredSourceTokens = @($requiredSourceTokens | ForEach-Object { $_.Replace($displayModeMarker, $DisplayMode) })
    $requiredInspectionTokens = @($requiredInspectionTokens | ForEach-Object { $_.Replace($displayModeMarker, $DisplayMode) })
  }
  elseif (![string]::IsNullOrWhiteSpace($DisplayMode)) {
    throw "ActionScript patch '$resolvedPatchPath' does not support DisplayMode configuration."
  }
  return [pscustomobject]@{
    Path = $resolvedPatchPath
    Script = [string]$patch.script
    Insertions = $parsedInsertions
    RequiredSourceTokens = $requiredSourceTokens
    RequiredInspectionTokens = $requiredInspectionTokens
    DisplayMode = if ($usesDisplayMode) { $DisplayMode } else { $null }
  }
}

function Get-BuildOrdinalOccurrenceCount {
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

function Apply-BuildActionScriptPatch {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][pscustomobject]$Patch
  )

  $resolvedSourcePath = Resolve-BuildRequiredFile -Path $SourcePath -Description "Exported ActionScript '$($Patch.Script)'"
  $source = [System.IO.File]::ReadAllText($resolvedSourcePath)
  foreach ($insertion in @($Patch.Insertions)) {
    $position = [string]$insertion.Position
    $anchor = [string]$insertion.Anchor
    $content = [string]$insertion.Content
    if ($position -cnotin @('before', 'after') -or [string]::IsNullOrEmpty($anchor)) {
      throw "ActionScript patch '$($Patch.Path)' contains an invalid insertion."
    }
    $anchorCount = Get-BuildOrdinalOccurrenceCount -Source $source -Value $anchor
    if ($anchorCount -ne 1) {
      throw "ActionScript patch '$($Patch.Path)' expected one '$($Patch.Script)' anchor but found $anchorCount."
    }
    $anchorIndex = $source.IndexOf($anchor, [System.StringComparison]::Ordinal)
    $insertionIndex = if ($position -ceq 'before') { $anchorIndex } else { $anchorIndex + $anchor.Length }
    $source = $source.Insert($insertionIndex, $content)
  }
  Assert-BuildScaleformSourceTokens -Source $source -RequiredTokens @($Patch.RequiredSourceTokens) -Description "Patched ActionScript '$($Patch.Script)'"
  Write-BuildUtf8WithoutBom -Path $resolvedSourcePath -Text $source
}

function Find-BuildExportedActionScript {
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

function ConvertTo-BuildNormalizedScaleformMovie {
  param(
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$WorkPath
  )

  $rawXmlPath = Join-Path $WorkPath 'compiled.xml'
  $normalizedXmlPath = Join-Path $WorkPath 'normalized.xml'
  if ((Test-Path -LiteralPath $rawXmlPath) -or
      (Test-Path -LiteralPath $normalizedXmlPath) -or
      (Test-Path -LiteralPath $OutputPath)) {
    throw "Scaleform normalization work paths must be fresh: $WorkPath"
  }
  Invoke-BuildJavaJar -JavaPath $JavaPath -JarPath $JpexsJarPath -Arguments @('-swf2xml', $InputPath, $rawXmlPath) -Description 'JPEXS movie XML export'
  [void](Resolve-BuildRequiredFile -Path $rawXmlPath -Description 'JPEXS movie XML export')

  [xml]$movie = Get-Content -LiteralPath $rawXmlPath -Raw
  $tagsNode = $movie.SelectSingleNode('/swf/tags')
  if ($null -eq $tagsNode) {
    throw 'Generated Scaleform movie does not contain a root tag collection.'
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
  try { $movie.Save($writer) } finally { $writer.Dispose() }

  Invoke-BuildJavaJar -JavaPath $JavaPath -JarPath $JpexsJarPath -Arguments @('-xml2swf', $normalizedXmlPath, $OutputPath) -Description 'JPEXS normalized movie rebuild'
  [void](Assert-BuildScaleformFile -Path $OutputPath -Description 'Normalized Scaleform movie')
}

function Get-BuildScaleformClassInventory {
  param([Parameter(Mandatory = $true)][string]$ScriptsDirectory)

  $definitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($scriptFile in @(Get-ChildItem -LiteralPath $ScriptsDirectory -Recurse -File -Filter '*.as')) {
    $source = [System.IO.File]::ReadAllText($scriptFile.FullName)
    $packageMatch = [regex]::Match($source, '(?m)^\s*package(?:\s+([A-Za-z_][A-Za-z0-9_.]*))?\s*$')
    $packageName = if ($packageMatch.Success) { [string]$packageMatch.Groups[1].Value } else { '' }
    foreach ($definitionMatch in [regex]::Matches($source, '(?m)^\s*(?:(?:public|internal|final|dynamic)\s+)*(?:class|interface)\s+([A-Za-z_][A-Za-z0-9_]*)\b')) {
      $definitionName = [string]$definitionMatch.Groups[1].Value
      $qualifiedName = if ([string]::IsNullOrEmpty($packageName)) { $definitionName } else { "$packageName.$definitionName" }
      if (!$definitions.Add($qualifiedName)) {
        throw "Scaleform movie exports duplicate definition '$qualifiedName'."
      }
    }
  }

  [string[]]$inventory = @($definitions)
  [System.Array]::Sort($inventory, [System.StringComparer]::Ordinal)
  if ($inventory.Count -eq 0) {
    throw 'Scaleform movie did not export any ActionScript definitions.'
  }
  return $inventory
}

function Get-BuildScaleformMovieDefinition {
  param([Parameter(Mandatory = $true)][string]$ManifestPath)

  $resolvedManifestPath = Resolve-BuildRequiredFile -Path $ManifestPath -Description 'Scaleform movie build manifest'
  [xml]$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw
  $build = $manifest.movieBuild
  if ($null -eq $build -or
      [string]::IsNullOrWhiteSpace([string]$build.name) -or
      [string]::IsNullOrWhiteSpace([string]$build.role) -or
      [string]::IsNullOrWhiteSpace([string]$build.outputFile) -or
      [string]::IsNullOrWhiteSpace([string]$build.documentClass) -or
      [string]::IsNullOrWhiteSpace([string]$build.className) -or
      [int]$build.stageWidth -le 0 -or
      [int]$build.stageHeight -le 0 -or
      [int]$build.frameRate -le 0) {
    throw "Invalid Scaleform movie build manifest: $resolvedManifestPath"
  }
  $requiredTokens = @($build.requiredTokens.token | ForEach-Object { [string]$_ })
  $forbiddenTokens = @($build.forbiddenTokens.token | ForEach-Object { [string]$_ })
  if ($requiredTokens.Count -eq 0 -or $forbiddenTokens.Count -eq 0) {
    throw "Scaleform movie manifest must declare required and forbidden tokens: $resolvedManifestPath"
  }
  return [pscustomobject]@{
    Name = [string]$build.name
    Role = [string]$build.role
    OutputFile = Assert-BuildScaleformRelativePath -Path ([string]$build.outputFile) -Description 'Scaleform manifest output file'
    ManifestPath = $resolvedManifestPath
    SourcePath = Resolve-BuildRequiredFile -Path (Join-Path (Split-Path -Parent $resolvedManifestPath) ([string]$build.documentClass)) -Description 'ActionScript entrypoint'
    ClassName = [string]$build.className
    StageWidth = [int]$build.stageWidth
    StageHeight = [int]$build.stageHeight
    FrameRate = [int]$build.frameRate
    RequiredTokens = $requiredTokens
    ForbiddenTokens = $forbiddenTokens
  }
}

function Invoke-BuildScaleformCompilation {
  param(
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$MxmlcJarPath,
    [Parameter(Mandatory = $true)][string]$FlexConfigPath,
    [Parameter(Mandatory = $true)][string]$PlayerGlobalPath,
    [Parameter(Mandatory = $true)][string]$FlexFrameworksPath,
    [Parameter(Mandatory = $true)][string]$EntrypointPath,
    [Parameter(Mandatory = $true)][string[]]$SourceRoots,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][int]$StageWidth,
    [Parameter(Mandatory = $true)][int]$StageHeight,
    [Parameter(Mandatory = $true)][int]$FrameRate
  )

  if (Test-Path -LiteralPath $OutputPath) {
    throw "Scaleform compiler output path is not fresh: $OutputPath"
  }
  if ($SourceRoots.Count -eq 0 -or @($SourceRoots | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -ne 0) {
    throw 'Apache Flex compilation requires at least one source root.'
  }
  $compilerArguments = @(
    "-load-config=$FlexConfigPath", '-compiler.library-path=', "-compiler.external-library-path=$PlayerGlobalPath",
    '-compiler.source-path'
  ) + @($SourceRoots) + @(
    '-compiler.debug=false', '-compiler.optimize=true', '-compiler.compress=true',
    '-compiler.omit-trace-statements=true', '-use-network=false', '-target-player=11.1.0', '-swf-version=12',
    '-default-size', $StageWidth, $StageHeight, "-default-frame-rate=$FrameRate", '-output', $OutputPath, $EntrypointPath
  )
  Push-Location $FlexFrameworksPath
  try {
    Invoke-BuildJavaJar -JavaPath $JavaPath -JarPath $MxmlcJarPath -Arguments $compilerArguments -Description 'Apache Flex Scaleform compilation'
  }
  finally { Pop-Location }
  [void](Assert-BuildScaleformFile -Path $OutputPath -Description 'Apache Flex compiler output')
}

function Assert-BuildScaleformMovie {
  param(
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$MoviePath,
    [Parameter(Mandatory = $true)][string]$WorkPath,
    [Parameter(Mandatory = $true)][pscustomobject]$Definition
  )

  [void](Assert-BuildScaleformFile -Path $MoviePath -Description "Generated $($Definition.Name) Scaleform movie")
  $exportDirectory = Join-Path $WorkPath 'inspection-scripts'
  Invoke-BuildJavaJar -JavaPath $JavaPath -JarPath $JpexsJarPath -Arguments @('-format', 'script:as', '-export', 'script', $exportDirectory, $MoviePath) -Description "JPEXS $($Definition.Name) ActionScript export"
  $inventory = @(Get-BuildScaleformClassInventory -ScriptsDirectory $exportDirectory)
  if (!($inventory -ccontains [string]$Definition.ClassName)) {
    throw "Scaleform movie '$($Definition.Name)' does not export declared class '$($Definition.ClassName)'. Exported classes: $([string]::Join(', ', $inventory))"
  }
  $validationSource = @(Get-ChildItem -LiteralPath $exportDirectory -Recurse -File -Filter '*.as' | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
  foreach ($requiredToken in @($Definition.RequiredTokens)) {
    if (!$validationSource.Contains([string]$requiredToken)) {
      throw "Scaleform movie '$($Definition.Name)' is missing required bytecode token '$requiredToken'."
    }
  }
  foreach ($forbiddenToken in @($Definition.ForbiddenTokens)) {
    if ($validationSource.Contains([string]$forbiddenToken)) {
      throw "Scaleform movie '$($Definition.Name)' contains forbidden bytecode token '$forbiddenToken'."
    }
  }
  return $inventory
}

function Publish-BuildScaleformFile {
  param(
    [Parameter(Mandatory = $true)][string]$CandidatePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedCandidate = Assert-BuildScaleformFile -Path $CandidatePath -Description 'Scaleform file candidate'
  $resolvedDestination = Publish-BuildFileAtomically -CandidatePath $resolvedCandidate -DestinationPath $DestinationPath -AllowedRoot $AllowedRoot -Description 'Scaleform file'
  [void](Assert-BuildScaleformFile -Path $resolvedDestination -Description 'Published Scaleform file')
}

function Invoke-BuildScaleformMovieBuild {
  param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$FlexSdkPath,
    [Parameter(Mandatory = $true)][string]$ScaleformSourceRoot,
    [switch]$KeepWork
  )

  $definition = Get-BuildScaleformMovieDefinition -ManifestPath $ManifestPath
  $resolvedJavaPath = Resolve-BuildRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-BuildRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-BuildRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  $resolvedScaleformSourceRoot = Resolve-BuildRequiredDirectory -Path $ScaleformSourceRoot -Description 'Scaleform source root'
  $sourceRootPrefix = (Get-BuildNormalizedFullPath -Path $resolvedScaleformSourceRoot) + [System.IO.Path]::DirectorySeparatorChar
  if (!(Get-BuildNormalizedFullPath -Path $definition.SourcePath).StartsWith($sourceRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Scaleform movie '$($definition.Name)' entrypoint is outside the configured Scaleform source root: $($definition.SourcePath)"
  }
  $mxmlcJarPath = Resolve-BuildRequiredFile -Path (Join-Path $resolvedFlexSdkPath 'lib\mxmlc.jar') -Description 'Apache Flex mxmlc compiler'
  $flexFrameworksPath = Resolve-BuildRequiredDirectory -Path (Join-Path $resolvedFlexSdkPath 'frameworks') -Description 'Apache Flex frameworks directory'
  $flexConfigPath = Resolve-BuildRequiredFile -Path (Join-Path $flexFrameworksPath 'flex-config.xml') -Description 'Apache Flex compiler configuration'
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
  $entrypointSourceRoot = Split-Path -Parent $definition.SourcePath
  $compilerSourceRoots = @($sourceRoot, $entrypointSourceRoot)
  if (!(Test-BuildSamePath -Left $entrypointSourceRoot -Right $resolvedScaleformSourceRoot)) {
    $compilerSourceRoots += $resolvedScaleformSourceRoot
  }

  try {
    $compiledPath = Join-Path $compileRoot 'compiled.swf'
    $normalizedPath = Join-Path $compileRoot $definition.OutputFile
    Invoke-BuildScaleformCompilation -JavaPath $resolvedJavaPath -MxmlcJarPath $mxmlcJarPath -FlexConfigPath $flexConfigPath -PlayerGlobalPath $playerGlobalMatches[0].FullName -FlexFrameworksPath $flexFrameworksPath -EntrypointPath $entrypointPath -SourceRoots $compilerSourceRoots -OutputPath $compiledPath -StageWidth $definition.StageWidth -StageHeight $definition.StageHeight -FrameRate $definition.FrameRate
    ConvertTo-BuildNormalizedScaleformMovie -JavaPath $resolvedJavaPath -JpexsJarPath $resolvedJpexsJarPath -InputPath $compiledPath -OutputPath $normalizedPath -WorkPath $compileRoot
    [void](Assert-BuildScaleformMovie -JavaPath $resolvedJavaPath -JpexsJarPath $resolvedJpexsJarPath -MoviePath $normalizedPath -WorkPath $compileRoot -Definition $definition)
    $destinationPath = Join-Path $resolvedOutputDirectory $definition.OutputFile
    Publish-BuildScaleformFile -CandidatePath $normalizedPath -DestinationPath $destinationPath -AllowedRoot $resolvedOutputDirectory
    return [pscustomobject]@{ Name = $definition.Name; Role = $definition.Role; OutputFile = $definition.OutputFile; Path = $destinationPath }
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Scaleform build files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-BuildRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}

function Invoke-BuildPatchedScaleformMovie {
  param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$PatchPath,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$FlexSdkPath,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [AllowEmptyString()][string]$DisplayMode,
    [switch]$KeepWork
  )

  $resolvedInputPath = Assert-BuildScaleformFile -Path $InputPath -Description 'Scaleform patch input'
  $resolvedJavaPath = Resolve-BuildRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsJarPath = Resolve-BuildRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-BuildRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  $patch = Get-BuildActionScriptPatch -PatchPath $PatchPath -DisplayMode $DisplayMode
  $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
  if (Test-Path -LiteralPath $resolvedOutputPath) {
    throw "Patched Scaleform output path is not fresh: $resolvedOutputPath"
  }
  $resolvedWorkDirectory = [System.IO.Path]::GetFullPath($WorkDirectory)
  New-Item -ItemType Directory -Force -Path $resolvedWorkDirectory | Out-Null
  $buildWorkDirectory = Join-Path $resolvedWorkDirectory ([guid]::NewGuid().ToString('N'))
  $exportDirectory = Join-Path $buildWorkDirectory 'exported'
  $inspectionDirectory = Join-Path $buildWorkDirectory 'inspection'
  New-Item -ItemType Directory -Path $exportDirectory, $inspectionDirectory | Out-Null
  try {
    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-format', 'script:as', '-selectclass', $patch.Script, '-onerror', 'abort', '-export', 'script', $exportDirectory, $resolvedInputPath) -Description "JPEXS $($patch.Script) ActionScript export"
    $sourcePath = Find-BuildExportedActionScript -ScriptsDirectory $exportDirectory -ScriptName $patch.Script
    Apply-BuildActionScriptPatch -SourcePath $sourcePath -Patch $patch
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedOutputPath) | Out-Null
    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-config', "flexSdkLocation=$resolvedFlexSdkPath", '-onerror', 'abort', '-importScript', $resolvedInputPath, $resolvedOutputPath, $exportDirectory) -Description "JPEXS $($patch.Script) ActionScript import"
    [void](Assert-BuildScaleformFile -Path $resolvedOutputPath -Description "Patched $($patch.Script) Scaleform movie")
    Invoke-BuildJavaJar -JavaPath $resolvedJavaPath -JarPath $resolvedJpexsJarPath -Arguments @('-format', 'script:as', '-onerror', 'abort', '-export', 'script', $inspectionDirectory, $resolvedOutputPath) -Description "JPEXS patched $($patch.Script) inspection export"
    $inspectionPath = Find-BuildExportedActionScript -ScriptsDirectory $inspectionDirectory -ScriptName $patch.Script
    Assert-BuildScaleformSourceTokens -Source ([System.IO.File]::ReadAllText($inspectionPath)) -RequiredTokens @($patch.RequiredInspectionTokens) -Description "Patched $($patch.Script) inspection"
    return $resolvedOutputPath
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Scaleform patch files retained at $buildWorkDirectory"
    }
    elseif (Test-Path -LiteralPath $buildWorkDirectory -PathType Container) {
      Assert-BuildRemovalPath -Path $buildWorkDirectory -AllowedRoot $resolvedWorkDirectory
      Remove-Item -LiteralPath $buildWorkDirectory -Recurse -Force
    }
  }
}

function Assert-BuildScaleformOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ExpectedFiles,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $resolvedDirectory = Resolve-BuildRequiredDirectory -Path $Directory -Description $Description
  $items = @(Get-ChildItem -LiteralPath $resolvedDirectory -Force)
  if (@($items | Where-Object { $_.PSIsContainer }).Count -ne 0) {
    throw "$Description contains unexpected directories."
  }
  Assert-BuildExactNames -Actual @($items.Name) -Expected $ExpectedFiles -Description "$Description file inventory"
  foreach ($fileName in $ExpectedFiles) {
    [void](Assert-BuildScaleformFile -Path (Join-Path $resolvedDirectory $fileName) -Description "$Description '$fileName'")
  }
}

function Invoke-BuildScaleformDirectoryMove {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  Move-Item -LiteralPath $Source -Destination $Destination
}

function Invoke-BuildScaleformDirectoryRemoval {
  param([Parameter(Mandatory = $true)][string]$Path)
  Remove-Item -LiteralPath $Path -Recurse -Force
}

function Publish-BuildScaleformOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$CandidateDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot
  )

  $resolvedCandidate = Resolve-BuildRequiredDirectory -Path $CandidateDirectory -Description 'Selected Scaleform output candidate'
  $resolvedDestination = [System.IO.Path]::GetFullPath($DestinationDirectory)
  $resolvedWorkDirectory = Resolve-BuildRequiredDirectory -Path $WorkDirectory -Description 'Scaleform publication work directory'
  Assert-BuildRemovalPath -Path $resolvedCandidate -AllowedRoot $AllowedRoot
  Assert-BuildRemovalPath -Path $resolvedDestination -AllowedRoot $AllowedRoot
  Assert-BuildRemovalPath -Path $resolvedWorkDirectory -AllowedRoot $AllowedRoot
  if (Test-Path -LiteralPath $resolvedDestination -PathType Leaf) {
    throw "Scaleform output destination is a file: $resolvedDestination"
  }
  $backupPath = Join-Path $resolvedWorkDirectory ('scaleform-publication-backup-' + [guid]::NewGuid().ToString('N'))
  Assert-BuildRemovalPath -Path $backupPath -AllowedRoot $AllowedRoot
  if (Test-Path -LiteralPath $backupPath) {
    throw "Refusing to replace preexisting Scaleform publication recovery material: $backupPath"
  }

  $existingOutputMoved = $false
  try {
    if (Test-Path -LiteralPath $resolvedDestination -PathType Container) {
      Invoke-BuildScaleformDirectoryMove -Source $resolvedDestination -Destination $backupPath
      $existingOutputMoved = $true
    }
    Invoke-BuildScaleformDirectoryMove -Source $resolvedCandidate -Destination $resolvedDestination
  }
  catch {
    $publicationError = $_
    if ($existingOutputMoved -and !(Test-Path -LiteralPath $resolvedDestination) -and (Test-Path -LiteralPath $backupPath -PathType Container)) {
      try { Invoke-BuildScaleformDirectoryMove -Source $backupPath -Destination $resolvedDestination }
      catch {
        throw "Scaleform publication failed and its prior output could not be restored. Recovery remains at '$backupPath'. Publication error: $($publicationError.Exception.Message) Recovery error: $($_.Exception.Message)"
      }
    }
    throw $publicationError
  }
  if ($existingOutputMoved) { Invoke-BuildScaleformDirectoryRemoval -Path $backupPath }
}

function Publish-BuildValidatedScaleformOutputSet {
  param(
    [Parameter(Mandatory = $true)][string]$CandidateDirectory,
    [Parameter(Mandatory = $true)][string]$DestinationDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-BuildScaleformOutputSet -Directory $CandidateDirectory -ExpectedFiles $ExpectedFiles -Description "$Description candidate"
  Publish-BuildScaleformOutputSet -CandidateDirectory $CandidateDirectory -DestinationDirectory $DestinationDirectory -WorkDirectory $WorkDirectory -AllowedRoot $AllowedRoot
  Assert-BuildScaleformOutputSet -Directory $DestinationDirectory -ExpectedFiles $ExpectedFiles -Description "Published $Description output"
}

function Resolve-BuildScaleformInputDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$RequiredFiles
  )

  $resolvedPath = Resolve-BuildRequiredDirectory -Path $Path -Description 'Scaleform input directory'
  $directPresent = @($RequiredFiles | Where-Object { !(Test-Path -LiteralPath (Join-Path $resolvedPath $_) -PathType Leaf) }).Count -eq 0
  $nestedPath = Join-Path $resolvedPath 'Interface'
  $nestedPresent = (Test-Path -LiteralPath $nestedPath -PathType Container) -and @($RequiredFiles | Where-Object { !(Test-Path -LiteralPath (Join-Path $nestedPath $_) -PathType Leaf) }).Count -eq 0
  if ($directPresent) { return $resolvedPath }
  if ($nestedPresent) { return $nestedPath }
  throw "Scaleform input directory does not contain the selected inputs: $([string]::Join(', ', $RequiredFiles))"
}

function Invoke-BuildScaleformJobs {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Jobs,
    [Parameter(Mandatory = $true)][string]$JavaPath,
    [Parameter(Mandatory = $true)][string]$JpexsJarPath,
    [Parameter(Mandatory = $true)][string]$FlexSdkPath,
    [string]$ScaleformSourceRoot,
    [string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$WorkDirectory,
    [Parameter(Mandatory = $true)][string]$AllowedRoot,
    [switch]$KeepWork
  )

  if ($Jobs.Count -eq 0) { return @() }
  $resolvedAllowedRoot = Get-BuildNormalizedFullPath -Path $AllowedRoot
  $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  $resolvedWorkRoot = [System.IO.Path]::GetFullPath($WorkDirectory)
  Assert-BuildRemovalPath -Path $resolvedOutputDirectory -AllowedRoot $resolvedAllowedRoot
  Assert-BuildRemovalPath -Path $resolvedWorkRoot -AllowedRoot $resolvedAllowedRoot
  if (Test-BuildOverlappingPaths -Left $resolvedOutputDirectory -Right $resolvedWorkRoot) {
    throw 'Scaleform output and work directories cannot overlap.'
  }

  $flexJobs = @($Jobs | Where-Object { $_.Kind -ceq 'Flex' })
  $patchJobs = @($Jobs | Where-Object { $_.Kind -ceq 'Patch' })
  $resolvedScaleformSourceRoot = $null
  if ($flexJobs.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($ScaleformSourceRoot)) {
      throw 'BuildSettings.ScaleformSourceRoot is required when a selected Scaleform job compiles a movie.'
    }
    $resolvedScaleformSourceRoot = Resolve-BuildRequiredDirectory -Path $ScaleformSourceRoot -Description 'Scaleform source root'
  }
  $resolvedInputDirectory = $null
  if ($patchJobs.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($InputDirectory)) {
      throw 'VanillaInterfacePath is required when a selected Scaleform job patches an input movie.'
    }
    $requiredInputs = @($patchJobs.Outputs | ForEach-Object { $_ } | ForEach-Object { [string]$_.InputFile } | Sort-Object -Unique)
    $resolvedInputDirectory = Resolve-BuildScaleformInputDirectory -Path $InputDirectory -RequiredFiles $requiredInputs
  }

  $resolvedJavaPath = Resolve-BuildRequiredFile -Path $JavaPath -Description 'Java executable'
  $resolvedJpexsPath = Resolve-BuildRequiredFile -Path $JpexsJarPath -Description 'JPEXS JAR'
  $resolvedFlexSdkPath = Resolve-BuildRequiredDirectory -Path $FlexSdkPath -Description 'Apache Flex SDK'
  New-Item -ItemType Directory -Force -Path $resolvedAllowedRoot | Out-Null
  New-Item -ItemType Directory -Force -Path $resolvedOutputDirectory, $resolvedWorkRoot | Out-Null
  $runDirectory = Join-Path $resolvedWorkRoot ('build-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $runDirectory | Out-Null
  $results = [System.Collections.Generic.List[object]]::new()
  try {
    $groupIndex = 0
    foreach ($group in @($flexJobs | Group-Object -Property OutputSet)) {
      $groupIndex++
      $candidateDirectory = Join-Path $runDirectory "flex-$groupIndex-candidate"
      $buildWorkDirectory = Join-Path $runDirectory "flex-$groupIndex-work"
      New-Item -ItemType Directory -Path $candidateDirectory, $buildWorkDirectory | Out-Null
      foreach ($job in @($group.Group)) {
        Write-Host -ForegroundColor Green "Building $($job.Name) Scaleform movie"
        $result = Invoke-BuildScaleformMovieBuild -ManifestPath $job.ManifestPath -OutputDirectory $candidateDirectory -WorkDirectory $buildWorkDirectory -JavaPath $resolvedJavaPath -JpexsJarPath $resolvedJpexsPath -FlexSdkPath $resolvedFlexSdkPath -ScaleformSourceRoot $resolvedScaleformSourceRoot -KeepWork:$KeepWork
        $expectedOutput = [string]$job.Outputs[0].OutputFile
        if ([string]$result.OutputFile -cne $expectedOutput) {
          throw "Scaleform job '$($job.Name)' emitted '$($result.OutputFile)' instead of '$expectedOutput'."
        }
        $results.Add([pscustomobject]@{ JobName = $job.Name; OutputSet = $job.OutputSet; OutputFile = $expectedOutput; Path = (Join-Path (Join-Path $resolvedOutputDirectory $job.OutputSet) $expectedOutput); VariantKey = $job.VariantKey })
      }
      $expectedFiles = @($group.Group | ForEach-Object { [string]$_.Outputs[0].OutputFile })
      Assert-BuildScaleformOutputSet -Directory $candidateDirectory -ExpectedFiles $expectedFiles -Description "Selected '$($group.Name)' Scaleform movies"
      $destinationDirectory = Join-Path $resolvedOutputDirectory $group.Name
      if (Test-Path -LiteralPath $destinationDirectory -PathType Leaf) {
        throw "Scaleform output set destination is a file: $destinationDirectory"
      }
      New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
      foreach ($fileName in $expectedFiles) {
        $destinationPath = Join-Path $destinationDirectory $fileName
        if (Test-Path -LiteralPath $destinationPath -PathType Container) {
          throw "Scaleform output destination is a directory: $destinationPath"
        }
      }
      foreach ($fileName in $expectedFiles) {
        Publish-BuildScaleformFile -CandidatePath (Join-Path $candidateDirectory $fileName) -DestinationPath (Join-Path $destinationDirectory $fileName) -AllowedRoot $resolvedAllowedRoot
      }
      foreach ($fileName in $expectedFiles) {
        [void](Assert-BuildScaleformFile -Path (Join-Path $destinationDirectory $fileName) -Description "Published Scaleform movie '$fileName'")
      }
    }

    foreach ($job in $patchJobs) {
      $groupIndex++
      $candidateDirectory = Join-Path $runDirectory "patch-$groupIndex-candidate"
      $patchWorkDirectory = Join-Path $runDirectory "patch-$groupIndex-work"
      New-Item -ItemType Directory -Path $candidateDirectory, $patchWorkDirectory | Out-Null
      foreach ($output in @($job.Outputs)) {
        $patchBuildParameters = @{
          InputPath = Join-Path $resolvedInputDirectory $output.InputFile
          OutputPath = Join-Path $candidateDirectory $output.OutputFile
          PatchPath = $job.PatchPath
          JavaPath = $resolvedJavaPath
          JpexsJarPath = $resolvedJpexsPath
          FlexSdkPath = $resolvedFlexSdkPath
          WorkDirectory = $patchWorkDirectory
          KeepWork = $KeepWork
        }
        $displayMode = [string](Get-BuildScaleformValue -InputObject $output -Name 'DisplayMode' -Description "Scaleform job '$($job.Name)' output '$($output.OutputFile)'")
        if (![string]::IsNullOrWhiteSpace($displayMode)) {
          $patchBuildParameters.DisplayMode = $displayMode
        }
        [void](Invoke-BuildPatchedScaleformMovie @patchBuildParameters)
        $results.Add([pscustomobject]@{ JobName = $job.Name; OutputSet = $job.OutputSet; OutputFile = $output.OutputFile; Path = (Join-Path (Join-Path $resolvedOutputDirectory $job.OutputSet) $output.OutputFile); VariantKey = $job.VariantKey })
      }
      $expectedFiles = @($job.Outputs | ForEach-Object { [string]$_.OutputFile })
      Publish-BuildValidatedScaleformOutputSet -CandidateDirectory $candidateDirectory -DestinationDirectory (Join-Path $resolvedOutputDirectory $job.OutputSet) -WorkDirectory $runDirectory -AllowedRoot $resolvedAllowedRoot -ExpectedFiles $expectedFiles -Description $job.Name
    }
    return @($results)
  }
  finally {
    if ($KeepWork) {
      Write-Host -ForegroundColor Yellow "Scaleform build files retained at $runDirectory"
    }
    elseif (Test-Path -LiteralPath $runDirectory -PathType Container) {
      $recoveryDirectories = @(Get-ChildItem -LiteralPath $runDirectory -Recurse -Directory -Filter 'scaleform-publication-backup-*')
      if ($recoveryDirectories.Count -gt 0) {
        Write-Host -ForegroundColor Yellow "Scaleform recovery material retained at $runDirectory"
      }
      else {
        Assert-BuildRemovalPath -Path $runDirectory -AllowedRoot $resolvedAllowedRoot
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
      }
    }
  }
}
