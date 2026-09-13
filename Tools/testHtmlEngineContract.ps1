<#
.SYNOPSIS
Validates the Canvas HTML Engine 2.0 contract and conformance-corpus integrity.

.DESCRIPTION
Checks frozen contract data, resource encodings and digests, out-of-band typed binding metadata, modeled absent/raw resources,
Canvas parser-route and semantic observations, deterministically constructed limit recipes, terminal results, and stateful failure observations. It does not parse HTML, CSS, or SVG or execute a runtime engine.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ContractCondition {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (!$Condition) {
    throw $Message
  }
}

function Assert-ContractExactSequence {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actual,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-ContractCondition -Condition ($Actual.Count -eq $Expected.Count) -Message "$Description count changed."
  for ($index = 0; $index -lt $Expected.Count; $index++) {
    Assert-ContractCondition -Condition ([string]$Actual[$index] -ceq [string]$Expected[$index]) -Message "$Description changed at index $index."
  }
}

function Assert-ContractExactSet {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Actual,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $actualSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($value in $Actual) {
    Assert-ContractCondition -Condition ($actualSet.Add([string]$value)) -Message "$Description contains duplicate value '$value'."
  }
  $expectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($value in $Expected) {
    Assert-ContractCondition -Condition ($expectedSet.Add([string]$value)) -Message "$Description expectation contains duplicate value '$value'."
  }
  Assert-ContractCondition -Condition $actualSet.SetEquals($expectedSet) -Message "$Description changed."
}

function Assert-ContractExactFields {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Description
  )

  Assert-ContractExactSet -Actual @($Value.PSObject.Properties.Name) -Expected $Expected -Description "$Description fields"
}

function Test-ContractInteger {
  param([Parameter(Mandatory = $true)][object]$Value)

  return $Value -is [byte] -or
    $Value -is [sbyte] -or
    $Value -is [int16] -or
    $Value -is [uint16] -or
    $Value -is [int32] -or
    $Value -is [uint32] -or
    $Value -is [int64] -or
    $Value -is [uint64]
}

function Test-ContractFiniteNumber {
  param([Parameter(Mandatory = $true)][object]$Value)

  if ($Value -is [bool] -or $Value -is [char] -or $Value -isnot [ValueType]) {
    return $false
  }
  try {
    $number = [double]$Value
    return ![double]::IsNaN($number) -and ![double]::IsInfinity($number)
  }
  catch {
    return $false
  }
}

function Test-ContractExactFieldSet {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Expected
  )

  $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($name in @($Value.PSObject.Properties.Name)) {
    if (!$actualSet.Add([string]$name)) { return $false }
  }
  $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($name in $Expected) {
    if (!$expectedSet.Add($name)) { return $false }
  }
  return $actualSet.SetEquals($expectedSet)
}

function Get-ContractBindingValidation {
  param(
    [Parameter(Mandatory = $true)][object]$Schema,
    [Parameter(Mandatory = $true)][string]$ConsumerNamespace,
    [Parameter(Mandatory = $true)][string]$EntryDocument,
    [Parameter(Mandatory = $true)][hashtable]$LimitById
  )

  $accepted = { [pscustomobject]@{ status = 'accepted'; reason = $null; key = $null } }
  $rejected = { param([string]$Reason, [AllowNull()][string]$Key) [pscustomobject]@{ status = 'rejected'; reason = $Reason; key = $Key } }
  if (!(Test-ContractExactFieldSet -Value $Schema -Expected @('schema','consumerNamespace','entryDocument','bindings'))) { return & $rejected 'unknown-top-level-field' $null }
  if ([string]$Schema.schema -cne 'VWCANVAS_HTML_BINDINGS/1') { return & $rejected 'wrong-schema' $null }
  if ([string]$Schema.consumerNamespace -cne $ConsumerNamespace) { return & $rejected 'wrong-consumer-association' $null }
  if ([string]$Schema.entryDocument -cne $EntryDocument) { return & $rejected 'wrong-entry-document-association' $null }
  if ($Schema.bindings -isnot [pscustomobject]) { return & $rejected 'invalid-bindings-shape' $null }

  [string[]]$bindingKeys = @($Schema.bindings.PSObject.Properties.Name)
  [Array]::Sort($bindingKeys, [StringComparer]::Ordinal)
  foreach ($key in $bindingKeys) {
    if ($key -cnotmatch '^[a-z][a-z0-9-]*$' -or $key.Length -gt [int]$LimitById['identifier-length'].value) { return & $rejected 'invalid-key' $key }
    $entry = $Schema.bindings.PSObject.Properties[$key].Value
    if (!(Test-ContractExactFieldSet -Value $entry -Expected @('type','default'))) { return & $rejected 'unknown-entry-field' $key }
    $bindingType = [string]$entry.type
    if (@('array','boolean','number','string') -cnotcontains $bindingType) { return & $rejected 'unknown-type' $key }
    $default = $entry.default
    switch ($bindingType) {
      'array' {
        if ($default -isnot [object[]]) { return & $rejected 'wrong-type-default' $key }
        if (@($default).Count -gt [int]$LimitById['repeat-items'].value) { return & $rejected 'array-too-long' $key }
        foreach ($item in @($default)) {
          if ($item -is [object[]]) { return & $rejected 'nested-array' $key }
          if ($item -is [pscustomobject] -or $item -is [Collections.IDictionary]) { return & $rejected 'nested-object' $key }
          if ($item -is [string]) {
            if ($item.Length -gt [int]$LimitById['string-code-units'].value) { return & $rejected 'string-too-long' $key }
          }
          elseif ($null -ne $item -and $item -isnot [bool]) {
            if ($item -is [char] -or $item -isnot [ValueType]) { return & $rejected 'wrong-type-default' $key }
            if (!(Test-ContractFiniteNumber -Value $item)) { return & $rejected 'non-finite-number' $key }
          }
        }
      }
      'boolean' { if ($default -isnot [bool]) { return & $rejected 'wrong-type-default' $key } }
      'number' {
        if ($default -is [bool] -or $default -is [char] -or $default -isnot [ValueType]) { return & $rejected 'wrong-type-default' $key }
        if (!(Test-ContractFiniteNumber -Value $default)) { return & $rejected 'non-finite-number' $key }
      }
      'string' {
        if ($default -isnot [string]) { return & $rejected 'wrong-type-default' $key }
        if ($default.Length -gt [int]$LimitById['string-code-units'].value) { return & $rejected 'string-too-long' $key }
      }
    }
  }
  return & $accepted
}

function Get-ContractSha256 {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)

  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-ContractUtf8Text {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $bytes = [IO.File]::ReadAllBytes($Path)
  Assert-ContractCondition -Condition (!($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) -Message "$Description contains a UTF-8 byte-order mark: $Path"
  $encoding = [Text.UTF8Encoding]::new($false, $true)
  try {
    $text = $encoding.GetString($bytes)
  }
  catch [Text.DecoderFallbackException] {
    throw "$Description is not valid UTF-8: $Path"
  }
  return [pscustomobject]@{ Bytes = $bytes; Text = $text }
}

function Get-ContractCanonicalTextInfo {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $loaded = Get-ContractUtf8Text -Path $Path -Description $Description
  $canonicalText = $loaded.Text.Replace("`r`n", "`n")
  Assert-ContractCondition -Condition ($canonicalText -cnotmatch "`r") -Message "$Description contains a bare carriage return."
  $canonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes($canonicalText)
  return [pscustomobject]@{
    Text = $loaded.Text
    CanonicalText = $canonicalText
    CanonicalBytes = $canonicalBytes
    CanonicalSha256 = Get-ContractSha256 -Bytes $canonicalBytes
  }
}

function New-ContractMeasurementMap {
  param([Parameter(Mandatory = $true)][hashtable]$LimitById)

  $measurements = @{}
  foreach ($limitId in $LimitById.Keys) {
    $measurements[[string]$limitId] = [long]0
  }
  return $measurements
}

function New-ContractSizedHtmlDocument {
  param(
    [Parameter(Mandatory = $true)][int]$ByteCount,
    [string]$BodyPrefix = '',
    [int]$BodyPrefixTokens = 0,
    [int]$BodyPrefixNodes = 0,
    [int]$MaximumPrefixStringCodeUnits = 0
  )

  $prefix = '<!doctype html><html><head><title>x</title></head><body>'
  $suffix = '</body></html>'
  $spanOverhead = '<span></span>'.Length
  $bodyBytes = $ByteCount - $prefix.Length - $BodyPrefix.Length - $suffix.Length
  Assert-ContractCondition -Condition ($bodyBytes -ge ($spanOverhead + 1)) -Message "Sized HTML document byte count $ByteCount is too small."
  $spanCount = [int][Math]::Ceiling($bodyBytes / [double](4096 + $spanOverhead))
  $textBytes = $bodyBytes - ($spanCount * $spanOverhead)
  Assert-ContractCondition -Condition ($textBytes -ge $spanCount -and $textBytes -le ($spanCount * 4096)) -Message "Sized HTML document $ByteCount cannot distribute bounded text."
  $baseTextLength = [int][Math]::Floor($textBytes / [double]$spanCount)
  $extraTextNodes = $textBytes % $spanCount
  $builder = [Text.StringBuilder]::new($ByteCount)
  $null = $builder.Append($prefix)
  $null = $builder.Append($BodyPrefix)
  $maximumTextLength = [Math]::Max(1, $MaximumPrefixStringCodeUnits)
  for ($index = 0; $index -lt $spanCount; $index++) {
    $nodeLength = $baseTextLength + $(if ($index -lt $extraTextNodes) { 1 } else { 0 })
    $null = $builder.Append('<span>').Append('x', $nodeLength).Append('</span>')
    $maximumTextLength = [Math]::Max($maximumTextLength, $nodeLength)
  }
  $null = $builder.Append($suffix)
  $text = $builder.ToString()
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
  Assert-ContractCondition -Condition ($bytes.Length -eq $ByteCount) -Message "Sized HTML document construction produced $($bytes.Length) rather than $ByteCount bytes."
  return [pscustomobject]@{
    Text = $text
    Bytes = $bytes
    HtmlTokens = 10 + $BodyPrefixTokens + (3 * $spanCount)
    DomNodes = 5 + $BodyPrefixNodes + (2 * $spanCount)
    DomDepth = 4
    ExpandedTextBytes = 1 + $textBytes
    MaximumStringCodeUnits = $maximumTextLength
  }
}

function Invoke-ContractRecipeGenerator {
  param(
    [Parameter(Mandatory = $true)][object]$Recipe,
    [Parameter(Mandatory = $true)][hashtable]$LimitById
  )

  $count = [int]$Recipe.parameters.count
  $measurements = New-ContractMeasurementMap -LimitById $LimitById
  switch ([string]$Recipe.generator) {
    'utf8-document' {
      $resource = New-ContractSizedHtmlDocument -ByteCount $count
      $measurements['source-file-bytes'] = $resource.Bytes.LongLength
      $measurements['aggregate-loaded-bytes'] = $resource.Bytes.LongLength
      $measurements['expanded-text-bytes'] = $resource.ExpandedTextBytes
      $measurements['html-tokens'] = $resource.HtmlTokens
      $measurements['expanded-dom-nodes'] = $resource.DomNodes
      $measurements['dom-depth'] = $resource.DomDepth
      $measurements['string-code-units'] = $resource.MaximumStringCodeUnits
    }
    'resource-set' {
      $resourceCount = [int][Math]::Ceiling($count / 65536.0)
      $baseResourceLength = [int][Math]::Floor($count / [double]$resourceCount)
      $extraResourceBytes = $count % $resourceCount
      $resources = [Collections.Generic.List[object]]::new($resourceCount)
      for ($index = 0; $index -lt $resourceCount; $index++) {
        $resourceLength = $baseResourceLength + $(if ($index -lt $extraResourceBytes) { 1 } else { 0 })
        if ($index -eq 0) {
          $includeMarkup = [Text.StringBuilder]::new()
          for ($resourceIndex = 1; $resourceIndex -lt $resourceCount; $resourceIndex++) { $null = $includeMarkup.Append('<vw-include src="r').Append($resourceIndex).Append('.html"></vw-include>') }
          $resources.Add((New-ContractSizedHtmlDocument -ByteCount $resourceLength -BodyPrefix $includeMarkup.ToString() -BodyPrefixTokens (2 * ($resourceCount - 1)) -BodyPrefixNodes ($resourceCount - 1) -MaximumPrefixStringCodeUnits 7))
        }
        else {
          $resources.Add((New-ContractSizedHtmlDocument -ByteCount $resourceLength))
        }
      }
      $resourceLengths = @($resources | ForEach-Object { $_.Bytes.LongLength })
      $measurements['source-file-bytes'] = if ($resourceLengths.Count -eq 0) { 0 } else { [long]($resourceLengths | Measure-Object -Maximum).Maximum }
      $measurements['aggregate-loaded-bytes'] = [long]($resourceLengths | Measure-Object -Sum).Sum
      $measurements['expanded-text-bytes'] = [long]($resources | ForEach-Object ExpandedTextBytes | Measure-Object -Sum).Sum - ($resourceCount - 1)
      $measurements['html-tokens'] = [long]($resources | ForEach-Object HtmlTokens | Measure-Object -Sum).Sum
      $measurements['expanded-dom-nodes'] = [long]($resources | ForEach-Object DomNodes | Measure-Object -Sum).Sum - (6 * ($resourceCount - 1))
      $measurements['dom-depth'] = [long]($resources | ForEach-Object DomDepth | Measure-Object -Maximum).Maximum
      $measurements['string-code-units'] = [long]($resources | ForEach-Object MaximumStringCodeUnits | Measure-Object -Maximum).Maximum
      $measurements['include-count'] = $resourceCount - 1
      $measurements['include-depth'] = 1
    }
    'composed-text' {
      $textNodes = [Collections.Generic.List[string]]::new()
      $remaining = $count
      while ($remaining -gt 0) {
        $nodeLength = [Math]::Min($remaining, 4096)
        $textNodes.Add(('x' * $nodeLength))
        $remaining -= $nodeLength
      }
      $nodeLengths = @($textNodes | ForEach-Object { [Text.UTF8Encoding]::new($false).GetByteCount($_) })
      $measurements['expanded-text-bytes'] = [long]($nodeLengths | Measure-Object -Sum).Sum
      $measurements['expanded-dom-nodes'] = $textNodes.Count
      $measurements['dom-depth'] = if ($textNodes.Count -gt 0) { 1 } else { 0 }
      $measurements['string-code-units'] = if ($textNodes.Count -eq 0) { 0 } else { [long]($textNodes | ForEach-Object Length | Measure-Object -Maximum).Maximum }
    }
    'token-stream' {
      $fixedTokens = 9
      $spanCount = [int][Math]::Ceiling(($count - $fixedTokens) / 4098.0)
      $textTokenCount = $count - $fixedTokens - (2 * $spanCount)
      Assert-ContractCondition -Condition ($spanCount -gt 0 -and $textTokenCount -ge $spanCount -and $textTokenCount -le (4096 * $spanCount)) -Message 'token-stream cannot distribute bounded decoded text.'
      $baseTextTokens = [int][Math]::Floor($textTokenCount / [double]$spanCount)
      $extraTextTokens = $textTokenCount % $spanCount
      $tokens = [Collections.Generic.List[string]]::new($count)
      @('doctype','start-html','start-head','start-title','end-title','end-head','start-body') | ForEach-Object { $tokens.Add($_) }
      $maximumStringLength = 0
      for ($spanIndex = 0; $spanIndex -lt $spanCount; $spanIndex++) {
        $tokens.Add('start-span')
        $nodeTextTokens = $baseTextTokens + $(if ($spanIndex -lt $extraTextTokens) { 1 } else { 0 })
        for ($textIndex = 0; $textIndex -lt $nodeTextTokens; $textIndex++) { $tokens.Add('character-reference-amp') }
        $tokens.Add('end-span')
        $maximumStringLength = [Math]::Max($maximumStringLength, $nodeTextTokens)
      }
      @('end-body','end-html') | ForEach-Object { $tokens.Add($_) }
      $measurements['html-tokens'] = $tokens.Count
      $measurements['expanded-text-bytes'] = $textTokenCount
      $measurements['expanded-dom-nodes'] = 4 + (2 * $spanCount)
      $measurements['dom-depth'] = 4
      $measurements['string-code-units'] = $maximumStringLength
    }
    'dom-tree' {
      $parentIndexes = [int[]]::new($count)
      if ($count -gt 0) {
        $parentIndexes[0] = -1
        for ($index = 1; $index -lt $count; $index++) { $parentIndexes[$index] = 0 }
      }
      $measurements['expanded-dom-nodes'] = $parentIndexes.Length
      $measurements['dom-depth'] = [Math]::Min($parentIndexes.Length, 2)
      $measurements['html-tokens'] = [long]$parentIndexes.Length * 2
    }
    'dom-chain' {
      $parentIndexes = [int[]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $parentIndexes[$index] = $index - 1 }
      $measurements['expanded-dom-nodes'] = $parentIndexes.Length
      $measurements['dom-depth'] = $parentIndexes.Length
      $measurements['html-tokens'] = [long]$parentIndexes.Length * 2
    }
    'element-attributes' {
      $attributeOrder = @('viewbox', 'id', 'class', 'data-vw-visible', 'width', 'height', 'x', 'y', 'fill', 'stroke', 'stroke-width', 'clip-rule', 'preserveaspectratio', 'fill-rule', 'stroke-linecap', 'stroke-linejoin', 'vector-effect')
      $attributeValues = @{'viewbox'='0 0 1 1';'id'='a';'class'='a';'data-vw-visible'='a';'width'='0';'height'='0';'x'='0';'y'='0';'fill'='none';'stroke'='none';'stroke-width'='0';'clip-rule'='nonzero';'preserveaspectratio'='none';'fill-rule'='nonzero';'stroke-linecap'='butt';'stroke-linejoin'='miter';'vector-effect'='none'}
      Assert-ContractCondition -Condition ($count -le $attributeOrder.Count) -Message 'element-attributes count exceeds the accepted SVG attribute catalog.'
      $attributes = [ordered]@{}
      foreach ($name in $attributeOrder[0..($count - 1)]) { $attributes[$name] = $attributeValues[$name] }
      $bindings = @{ a = @{ type = 'boolean'; default = $true } }
      Assert-ContractCondition -Condition ($bindings.a.default -eq $true) -Message 'element-attributes did not construct its required local binding.'
      $measurements['attributes-per-element'] = $attributes.Count
      $measurements['html-tokens'] = 11
      $measurements['expanded-dom-nodes'] = 5
      $measurements['dom-depth'] = 3
      $measurements['identifier-length'] = if ($attributes.Contains('id') -or $attributes.Contains('class')) { 1 } else { 0 }
      $measurements['string-code-units'] = [long]($attributes.Values | ForEach-Object Length | Measure-Object -Maximum).Maximum
    }
    'decoded-string' {
      $decoded = 'x' * $count
      $measurements['string-code-units'] = $decoded.Length
      $measurements['expanded-text-bytes'] = [Text.UTF8Encoding]::new($false).GetByteCount($decoded)
      $measurements['html-tokens'] = 12
      $measurements['expanded-dom-nodes'] = 6
      $measurements['dom-depth'] = 4
    }
    'identifier' {
      $identifier = if ($count -eq 0) { '' } else { 'a' + ('b' * ($count - 1)) }
      $measurements['identifier-length'] = $identifier.Length
      $measurements['string-code-units'] = $identifier.Length
      $measurements['attributes-per-element'] = 1
      $measurements['html-tokens'] = 9
      $measurements['expanded-dom-nodes'] = 4
      $measurements['dom-depth'] = 3
    }
    'include-graph' {
      $includeParents = [int[]]::new($count)
      $measurements['include-count'] = $includeParents.Length
      $measurements['include-depth'] = if ($count -gt 0) { 1 } else { 0 }
      $measurements['expanded-dom-nodes'] = [long]$includeParents.Length + 1
      $measurements['dom-depth'] = if ($count -gt 0) { 2 } else { 1 }
    }
    'include-chain' {
      $includeParents = [int[]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $includeParents[$index] = $index - 1 }
      $measurements['include-count'] = $includeParents.Length
      $measurements['include-depth'] = $includeParents.Length
      $measurements['expanded-dom-nodes'] = [long]$includeParents.Length + 1
      $measurements['dom-depth'] = [long]$includeParents.Length + 1
    }
    'stylesheet-set' {
      $stylesheets = [Collections.Generic.List[string]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $stylesheets.Add('.a{color:transparent;}') }
      $measurements['stylesheet-count'] = $stylesheets.Count
      $measurements['css-rules'] = $stylesheets.Count
      $measurements['selectors-per-group'] = [Math]::Min($stylesheets.Count, 1)
      $measurements['selector-terms'] = [Math]::Min($stylesheets.Count, 1)
      $measurements['declarations-per-rule'] = [Math]::Min($stylesheets.Count, 1)
    }
    'css-rule-set' {
      $rules = [Collections.Generic.List[string]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $rules.Add('.a{color:transparent;}') }
      $stylesheet = [string]::Concat($rules)
      Assert-ContractCondition -Condition ($stylesheet.Length -gt 0) -Message 'css-rule-set did not construct a stylesheet.'
      $measurements['stylesheet-count'] = 1
      $measurements['css-rules'] = $rules.Count
      $measurements['selectors-per-group'] = 1
      $measurements['selector-terms'] = 1
      $measurements['declarations-per-rule'] = 1
    }
    'selector-group' {
      $selectors = [Collections.Generic.List[string]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $selectors.Add('.a') }
      $rule = [string]::Join(',', $selectors) + '{color:transparent;}'
      Assert-ContractCondition -Condition ($rule.Length -gt 0) -Message 'selector-group did not construct a rule.'
      $measurements['stylesheet-count'] = 1
      $measurements['css-rules'] = 1
      $measurements['selectors-per-group'] = $selectors.Count
      $measurements['selector-terms'] = [Math]::Min($selectors.Count, 1)
      $measurements['declarations-per-rule'] = 1
    }
    'selector-chain' {
      $terms = [Collections.Generic.List[string]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $terms.Add('div') }
      $rule = [string]::Join(' ', $terms) + '{color:transparent;}'
      Assert-ContractCondition -Condition ($rule.Length -gt 0) -Message 'selector-chain did not construct a rule.'
      $measurements['stylesheet-count'] = 1
      $measurements['css-rules'] = 1
      $measurements['selectors-per-group'] = 1
      $measurements['selector-terms'] = $terms.Count
      $measurements['declarations-per-rule'] = 1
    }
    'declaration-set' {
      $declarations = [Collections.Generic.List[string]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $declarations.Add(('--a{0:d3}:0' -f $index)) }
      $rule = '.a{' + [string]::Join(';', $declarations) + '}'
      Assert-ContractCondition -Condition ($rule.Length -gt 0) -Message 'declaration-set did not construct a rule.'
      $measurements['stylesheet-count'] = 1
      $measurements['css-rules'] = 1
      $measurements['selectors-per-group'] = 1
      $measurements['selector-terms'] = 1
      $measurements['declarations-per-rule'] = $declarations.Count
      $measurements['identifier-length'] = 4
    }
    'variable-chain' {
      $declarations = [Collections.Generic.List[string]]::new($count + 1)
      for ($index = 1; $index -le $count; $index++) {
        $value = if ($index -eq $count) { '#ffffff' } else { 'var(--v{0:d2})' -f ($index + 1) }
        $declarations.Add(('--v{0:d2}:{1}' -f $index, $value))
      }
      $declarations.Add('color:var(--v01)')
      $rule = '.a{' + [string]::Join(';', $declarations) + '}'
      Assert-ContractCondition -Condition ($rule.Length -gt 0) -Message 'variable-chain did not construct a rule.'
      $measurements['stylesheet-count'] = 1
      $measurements['css-rules'] = 1
      $measurements['selectors-per-group'] = 1
      $measurements['selector-terms'] = 1
      $measurements['declarations-per-rule'] = $declarations.Count
      $measurements['variable-depth'] = $count
      $measurements['identifier-length'] = 3
    }
    'repeat-items' {
      $items = [object[]]::new($count)
      $measurements['repeat-items'] = $items.Length
      $measurements['expanded-dom-nodes'] = [long]$items.Length + 1
      $measurements['dom-depth'] = if ($count -gt 0) { 2 } else { 1 }
      $measurements['generic-components'] = 1
    }
    'state-alternatives' {
      $states = [bool[]]::new($count)
      $measurements['state-alternatives'] = $states.Length
      $measurements['expanded-dom-nodes'] = [long]$states.Length + 1
      $measurements['dom-depth'] = if ($count -gt 0) { 2 } else { 1 }
      $measurements['generic-components'] = $states.Length
    }
    'svg-tree' {
      $nodes = [Collections.Generic.List[string]]::new($count)
      if ($count -gt 0) {
        $nodes.Add('svg')
        for ($index = 1; $index -lt $count; $index++) { $nodes.Add('path') }
      }
      $measurements['svg-nodes'] = $nodes.Count
      $measurements['svg-depth'] = [Math]::Min($nodes.Count, 2)
      if ($nodes.Count -gt 1) {
        $measurements['path-tokens'] = 3
        $measurements['path-commands'] = 1
      }
    }
    'svg-chain' {
      $parentIndexes = [int[]]::new($count)
      for ($index = 0; $index -lt $count; $index++) { $parentIndexes[$index] = $index - 1 }
      $measurements['svg-nodes'] = $parentIndexes.Length
      $measurements['svg-depth'] = $parentIndexes.Length
    }
    'path-token-stream' {
      Assert-ContractCondition -Condition ($count -eq 2048 -or $count -eq 2049) -Message 'path-token-stream is defined only for the v2 at/over probes.'
      $tokens = [Collections.Generic.List[string]]::new($count)
      $tokens.Add('M'); $tokens.Add('0'); $tokens.Add('0')
      $segments = [Collections.Generic.List[string]]::new(295)
      $segments.Add('M0 0')
      for ($index = 0; $index -lt 292; $index++) {
        $segments.Add('C0 0 0 0 0 0')
        $tokens.Add('C')
        for ($number = 0; $number -lt 6; $number++) { $tokens.Add('0') }
      }
      while ($tokens.Count -lt $count) { $tokens.Add('Z'); $segments.Add('Z') }
      $path = [string]::Concat($segments)
      $measurements['svg-nodes'] = 2
      $measurements['svg-depth'] = 2
      $measurements['path-tokens'] = $tokens.Count
      $measurements['path-commands'] = @($tokens | Where-Object { $_ -cmatch '^[A-Za-z]$' }).Count
      $measurements['string-code-units'] = $path.Length
    }
    'path-command-stream' {
      $tokens = [Collections.Generic.List[string]]::new($count * 3)
      $segments = [Collections.Generic.List[string]]::new($count)
      if ($count -gt 0) {
        $segments.Add('M0 0'); $tokens.Add('M'); $tokens.Add('0'); $tokens.Add('0')
        for ($index = 1; $index -lt $count; $index++) {
          $segments.Add('L0 0'); $tokens.Add('L'); $tokens.Add('0'); $tokens.Add('0')
        }
      }
      $path = [string]::Concat($segments)
      $measurements['svg-nodes'] = 2
      $measurements['svg-depth'] = 2
      $measurements['path-tokens'] = $tokens.Count
      $measurements['path-commands'] = @($tokens | Where-Object { $_ -cmatch '^[A-Za-z]$' }).Count
      $measurements['string-code-units'] = $path.Length
    }
    'component-tree' {
      $components = [int[]]::new($count)
      $measurements['generic-components'] = $components.Length
      $measurements['expanded-dom-nodes'] = [long]$components.Length + 1
      $measurements['dom-depth'] = if ($count -gt 0) { 2 } else { 1 }
    }
    'render-tree' {
      $objects = [int[]]::new($count)
      $componentCount = [Math]::Min($objects.Length, 512)
      for ($index = 0; $index -lt $objects.Length; $index++) { $objects[$index] = $index % $componentCount }
      $measurements['native-display-objects'] = $objects.Length
      $measurements['generic-components'] = $componentCount
      $measurements['expanded-dom-nodes'] = $componentCount
      $measurements['dom-depth'] = if ($count -gt 0) { 2 } else { 0 }
    }
    default { throw "Unknown recipe generator '$($Recipe.generator)'." }
  }
  return $measurements
}

function Assert-ContractTerminalResult {
  param(
    [Parameter(Mandatory = $true)][object]$Result,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string]$ContractId,
    [Parameter(Mandatory = $true)][string[]]$Stages,
    [Parameter(Mandatory = $true)][string[]]$Codes,
    [Parameter(Mandatory = $true)][object]$CodeStages,
    [Parameter(Mandatory = $true)][hashtable]$LimitById
  )

  $resultFields = @('contract', 'status', 'stage', 'code', 'resource', 'offset', 'limitId', 'committed')
  Assert-ContractExactFields -Value $Result -Expected $resultFields -Description $Description
  Assert-ContractCondition -Condition ($Result.contract -ceq $ContractId) -Message "$Description has the wrong contract."
  Assert-ContractCondition -Condition ($Stages -ccontains [string]$Result.stage) -Message "$Description has unknown stage '$($Result.stage)'."
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$Result.resource)) -Message "$Description has no resource."
  Assert-ContractCondition -Condition ($null -eq $Result.offset -or ((Test-ContractInteger -Value $Result.offset) -and [long]$Result.offset -ge 0)) -Message "$Description has an invalid offset."

  switch ([string]$Result.status) {
    'accepted' {
      Assert-ContractCondition -Condition ([string]$Result.stage -ceq 'lifecycle') -Message "$Description accepted outside lifecycle."
      Assert-ContractCondition -Condition ($null -eq $Result.code) -Message "$Description accepted with a code."
      Assert-ContractCondition -Condition ($null -eq $Result.offset) -Message "$Description accepted with an offset."
      Assert-ContractCondition -Condition ($null -eq $Result.limitId) -Message "$Description accepted with a limit ID."
      Assert-ContractCondition -Condition ($Result.committed -eq $true) -Message "$Description accepted without committing."
    }
    'rejected' {
      Assert-ContractCondition -Condition ($Codes -ccontains [string]$Result.code) -Message "$Description has unknown code '$($Result.code)'."
      Assert-ContractCondition -Condition ([string]$Result.code -cne 'cancelled') -Message "$Description uses cancelled as a rejection code."
      Assert-ContractCondition -Condition ($Result.committed -eq $false) -Message "$Description rejected but committed."
      $allowedStages = @($CodeStages.([string]$Result.code))
      Assert-ContractCondition -Condition ($allowedStages -ccontains [string]$Result.stage) -Message "$Description uses code '$($Result.code)' at disallowed stage '$($Result.stage)'."
      if ([string]$Result.code -ceq 'limit-exceeded') {
        Assert-ContractCondition -Condition ($LimitById.ContainsKey([string]$Result.limitId)) -Message "$Description has an unknown limit ID."
        Assert-ContractCondition -Condition ([string]$Result.stage -ceq [string]$LimitById[[string]$Result.limitId].stage) -Message "$Description limit stage does not match its limit."
      }
      else {
        Assert-ContractCondition -Condition ($null -eq $Result.limitId) -Message "$Description has a limit ID for a non-limit error."
      }
    }
    'cancelled' {
      Assert-ContractCondition -Condition ([string]$Result.code -ceq 'cancelled') -Message "$Description cancelled with another code."
      Assert-ContractCondition -Condition ($null -eq $Result.offset) -Message "$Description cancelled with an offset."
      Assert-ContractCondition -Condition ($null -eq $Result.limitId) -Message "$Description cancelled with a limit ID."
      Assert-ContractCondition -Condition ($Result.committed -eq $false) -Message "$Description cancelled but committed."
    }
    default { throw "$Description has unknown status '$($Result.status)'." }
  }
}

function Assert-ContractCandidateError {
  param(
    [Parameter(Mandatory = $true)][object]$ErrorRecord,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][string[]]$Stages,
    [Parameter(Mandatory = $true)][string[]]$Codes,
    [Parameter(Mandatory = $true)][object]$CodeStages,
    [Parameter(Mandatory = $true)][hashtable]$LimitById
  )

  Assert-ContractExactFields -Value $ErrorRecord -Expected @('stage', 'code', 'resource', 'offset', 'resourceOrder', 'limitId') -Description $Description
  Assert-ContractCondition -Condition ($Stages -ccontains [string]$ErrorRecord.stage) -Message "$Description has an unknown stage."
  Assert-ContractCondition -Condition ($Codes -ccontains [string]$ErrorRecord.code) -Message "$Description has an unknown code."
  Assert-ContractCondition -Condition (@($CodeStages.([string]$ErrorRecord.code)) -ccontains [string]$ErrorRecord.stage) -Message "$Description uses a code at a disallowed stage."
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$ErrorRecord.resource)) -Message "$Description has no resource."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $ErrorRecord.resourceOrder) -and [long]$ErrorRecord.resourceOrder -ge 0) -Message "$Description has an invalid resource order."
  Assert-ContractCondition -Condition ($null -eq $ErrorRecord.offset -or ((Test-ContractInteger -Value $ErrorRecord.offset) -and [long]$ErrorRecord.offset -ge 0)) -Message "$Description has an invalid offset."
  if ([string]$ErrorRecord.code -ceq 'limit-exceeded') {
    Assert-ContractCondition -Condition ($LimitById.ContainsKey([string]$ErrorRecord.limitId)) -Message "$Description has an unknown limit."
  }
  else {
    Assert-ContractCondition -Condition ($null -eq $ErrorRecord.limitId) -Message "$Description has an unexpected limit ID."
  }
}

function Compare-ContractCandidateError {
  param(
    [Parameter(Mandatory = $true)][object]$Left,
    [Parameter(Mandatory = $true)][object]$Right,
    [Parameter(Mandatory = $true)][hashtable]$StageIndex,
    [Parameter(Mandatory = $true)][hashtable]$CodeIndex,
    [Parameter(Mandatory = $true)][hashtable]$LimitIndex
  )

  $leftStage = [int]$StageIndex[[string]$Left.stage]
  $rightStage = [int]$StageIndex[[string]$Right.stage]
  if ($leftStage -ne $rightStage) { return $leftStage.CompareTo($rightStage) }
  $resourceComparison = ([long]$Left.resourceOrder).CompareTo([long]$Right.resourceOrder)
  if ($resourceComparison -ne 0) { return $resourceComparison }
  if ($null -eq $Left.offset -and $null -ne $Right.offset) { return 1 }
  if ($null -ne $Left.offset -and $null -eq $Right.offset) { return -1 }
  if ($null -ne $Left.offset) {
    $offsetComparison = ([long]$Left.offset).CompareTo([long]$Right.offset)
    if ($offsetComparison -ne 0) { return $offsetComparison }
  }
  $codeComparison = ([int]$CodeIndex[[string]$Left.code]).CompareTo([int]$CodeIndex[[string]$Right.code])
  if ($codeComparison -ne 0) { return $codeComparison }
  if ([string]$Left.code -ceq 'limit-exceeded') {
    $limitComparison = ([int]$LimitIndex[[string]$Left.limitId]).CompareTo([int]$LimitIndex[[string]$Right.limitId])
    if ($limitComparison -ne 0) { return $limitComparison }
  }
  return [string]::CompareOrdinal([string]$Left.resource, [string]$Right.resource)
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$contractPath = Join-Path $repositoryRoot 'Contracts/html-engine-v2.json'
$corpusRoot = Join-Path $repositoryRoot 'Tests/HtmlEngine'
$corpusPath = Join-Path $corpusRoot 'corpus.json'
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $corpusRoot 'fixtures'))
$expectedContractDigest = '330be6153ebea539f27ec154aecc854689fd4605d9a59b225387815d820ececd'
$expectedContract = 'VWCANVAS_HTML/2'
$expectedStages = @('load', 'parse', 'compose', 'style', 'layout', 'asset', 'bind', 'render', 'lifecycle')
$expectedCodes = @('unsupported-contract', 'invalid-path', 'resource-unavailable', 'invalid-encoding', 'malformed-syntax', 'unsupported-feature', 'invalid-value', 'duplicate-identity', 'unresolved-reference', 'cycle', 'limit-exceeded', 'adapter-failure', 'cancelled')
$expectedStatuses = @('accepted', 'rejected', 'cancelled')
$expectedCategories = @('valid', 'boundary', 'malformed', 'hostile', 'cycle', 'traversal', 'unsupported-feature', 'exhaustion')
$expectedResourceKinds = @('document', 'stylesheet', 'svg', 'recipe')
$expectedResourceSources = @('file', 'absent', 'base64')
$expectedEvidenceKinds = @('physical', 'declarative-recipe', 'modeled-resource')
$expectedSpecAssertions = @('css-variable-valid-substitution', 'css-variable-missing', 'css-variable-terminal-type-mismatch', 'css-variable-cycle', 'css-variable-depth-at-limit', 'css-variable-depth-over-limit', 'standalone-svg-external', 'svg-omitted-defaults')
$expectedStandardElements = @('html', 'head', 'title', 'meta', 'link', 'style', 'body', 'main', 'header', 'footer', 'section', 'div', 'span', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'br', 'hr', 'ul', 'ol', 'li', 'button', 'template', 'img', 'svg', 'path')
$expectedCustomElements = @('vw-include', 'vw-use', 'vw-repeat', 'vw-state', 'vw-meter')
$expectedReservedGeneric = @('vw-icon', 'vw-mask', 'vw-provider-symbol', 'vw-symbol')
$expectedReservedConsumer = @('vw-compass-tape', 'vw-contact-radar', 'vw-scanner-overlay', 'vw-status-effect-bar', 'vw-threat-alert', 'vw-vanilla-target')
$expectedGenerators = @{
  'source-file-bytes' = @('utf8-document', 'raw-resource-set')
  'aggregate-loaded-bytes' = @('resource-set', 'raw-resource-set')
  'expanded-text-bytes' = @('composed-text', 'composed-tree')
  'html-tokens' = @('token-stream', 'html-token-stream')
  'expanded-dom-nodes' = @('dom-tree', 'composed-tree')
  'dom-depth' = @('dom-chain', 'composed-tree')
  'attributes-per-element' = @('element-attributes', 'html-token-stream')
  'string-code-units' = @('decoded-string', 'html-token-stream')
  'identifier-length' = @('identifier', 'html-token-stream')
  'include-count' = @('include-graph', 'composed-tree')
  'include-depth' = @('include-chain', 'composed-tree')
  'stylesheet-count' = @('stylesheet-set', 'styled-tree')
  'css-rules' = @('css-rule-set', 'styled-tree')
  'selectors-per-group' = @('selector-group', 'styled-tree')
  'selector-terms' = @('selector-chain', 'styled-tree')
  'declarations-per-rule' = @('declaration-set', 'styled-tree')
  'variable-depth' = @('variable-chain', 'styled-tree')
  'repeat-items' = @('repeat-items', 'composed-tree')
  'state-alternatives' = @('state-alternatives', 'composed-tree')
  'svg-nodes' = @('svg-tree', 'asset-tree')
  'svg-depth' = @('svg-chain', 'asset-tree')
  'path-tokens' = @('path-token-stream', 'asset-tree')
  'path-commands' = @('path-command-stream', 'asset-tree')
  'generic-components' = @('component-tree', 'layout-tree')
  'native-display-objects' = @('render-tree', 'render-tree')
}
$requiredRecipeCompanions = @{
  'utf8-document'=@('aggregate-loaded-bytes','expanded-text-bytes','html-tokens','expanded-dom-nodes','dom-depth','string-code-units'); 'resource-set'=@('source-file-bytes','expanded-text-bytes','html-tokens','expanded-dom-nodes','dom-depth','string-code-units','include-count','include-depth'); 'composed-text'=@('expanded-dom-nodes','dom-depth','string-code-units'); 'token-stream'=@('expanded-text-bytes','expanded-dom-nodes','dom-depth','string-code-units');
  'dom-tree'=@('html-tokens','dom-depth'); 'dom-chain'=@('html-tokens','expanded-dom-nodes'); 'element-attributes'=@('html-tokens','expanded-dom-nodes','dom-depth','identifier-length','string-code-units'); 'decoded-string'=@('expanded-text-bytes','html-tokens','expanded-dom-nodes','dom-depth');
  'identifier'=@('html-tokens','string-code-units','attributes-per-element','expanded-dom-nodes','dom-depth'); 'include-graph'=@('expanded-dom-nodes','dom-depth','include-depth'); 'include-chain'=@('expanded-dom-nodes','dom-depth','include-count');
  'stylesheet-set'=@('css-rules','selectors-per-group','selector-terms','declarations-per-rule'); 'css-rule-set'=@('stylesheet-count','selectors-per-group','selector-terms','declarations-per-rule');
  'selector-group'=@('stylesheet-count','css-rules','selector-terms','declarations-per-rule'); 'selector-chain'=@('stylesheet-count','css-rules','selectors-per-group','declarations-per-rule');
  'declaration-set'=@('stylesheet-count','css-rules','selectors-per-group','selector-terms','identifier-length'); 'variable-chain'=@('stylesheet-count','css-rules','selectors-per-group','selector-terms','declarations-per-rule','identifier-length');
  'repeat-items'=@('expanded-dom-nodes','dom-depth','generic-components'); 'state-alternatives'=@('expanded-dom-nodes','dom-depth','generic-components'); 'svg-tree'=@('svg-depth','path-tokens','path-commands');
  'svg-chain'=@('svg-nodes'); 'path-token-stream'=@('string-code-units','svg-nodes','svg-depth','path-commands'); 'path-command-stream'=@('string-code-units','svg-nodes','svg-depth','path-tokens');
  'component-tree'=@('expanded-dom-nodes','dom-depth'); 'render-tree'=@('expanded-dom-nodes','dom-depth','generic-components')
}

Assert-ContractCondition -Condition (Test-Path -LiteralPath $contractPath -PathType Leaf) -Message "HTML contract is missing: $contractPath"
Assert-ContractCondition -Condition (Test-Path -LiteralPath $corpusPath -PathType Leaf) -Message "HTML corpus is missing: $corpusPath"
Assert-ContractCondition -Condition (Test-Path -LiteralPath $fixtureRoot -PathType Container) -Message "HTML fixture root is missing: $fixtureRoot"
Assert-ContractCondition -Condition (Test-ContractFiniteNumber -Value 1.5) -Message 'Finite-number predicate rejected a finite number.'
Assert-ContractCondition -Condition (!(Test-ContractFiniteNumber -Value ([double]::NaN))) -Message 'Finite-number predicate accepted NaN.'
Assert-ContractCondition -Condition (!(Test-ContractFiniteNumber -Value ([double]::PositiveInfinity))) -Message 'Finite-number predicate accepted positive infinity.'
Assert-ContractCondition -Condition (!(Test-ContractFiniteNumber -Value ([double]::NegativeInfinity))) -Message 'Finite-number predicate accepted negative infinity.'

$contractInfo = Get-ContractCanonicalTextInfo -Path $contractPath -Description 'HTML contract'
$corpusInfo = Get-ContractCanonicalTextInfo -Path $corpusPath -Description 'HTML corpus'
Assert-ContractCondition -Condition ($contractInfo.CanonicalSha256 -ceq $expectedContractDigest) -Message "Normative HTML manifest changed without updating its reviewed canonical digest. Found $($contractInfo.CanonicalSha256)."
$contract = $contractInfo.Text | ConvertFrom-Json -Depth 100
$corpus = $corpusInfo.Text | ConvertFrom-Json -Depth 100

Assert-ContractExactFields -Value $contract -Expected @('contract','version','status','runtimeImplemented','independentVersionDomains','inputPipeline','syntax','identifiers','elements','css','styleResolution','layout','svgPath','standaloneSvg','assets','bindings','snapshotUpdates','recipeSchema','semanticObservationSchema','limits','terminalResult','failureModel','transaction') -Description 'HTML manifest'
Assert-ContractCondition -Condition ($contract.contract -ceq $expectedContract) -Message 'HTML contract identifier changed.'
Assert-ContractCondition -Condition ($contract.version -eq 2) -Message 'HTML contract version changed.'
Assert-ContractCondition -Condition ($contract.runtimeImplemented -eq $false) -Message 'HTML manifest claims a runtime implementation.'
Assert-ContractCondition -Condition ($contract.syntax.recovery -ceq 'none' -and $contract.syntax.secondaryParser -ceq 'none') -Message 'HTML parser recovery or fallback changed.'
Assert-ContractCondition -Condition ($contract.failureModel.oneTerminalResult -eq $true -and $contract.failureModel.secondaryParser -ceq 'none') -Message 'Failure model no longer requires one terminal result and no fallback parser.'
Assert-ContractCondition -Condition ($contract.transaction.partialPublication -ceq 'forbidden' -and $contract.transaction.replacementFailure -ceq 'preserve-existing-committed-content') -Message 'Atomic replacement behavior changed.'
Assert-ContractExactFields -Value $contract.inputPipeline -Expected @('contract','runtimeResourceExtensions','orderedSteps','acquisition','byteLimits','decoder','decodedRepresentation','parserRoutes','fragmentRule','parserOwnership','parsePasses','parsePassScope','secondaryParser','recoveryParser','forbiddenBackends','forbiddenPurposes','requiredForbiddenBackendInvocations','observationFields','inputObservationFields','acquisitionOutcomes','decoderOutcomes','textTypes','failures') -Description 'Input pipeline'
Assert-ContractCondition -Condition ($contract.inputPipeline.contract -ceq 'VWCANVAS_HTML_INPUT/1' -and $contract.inputPipeline.parserOwnership -ceq 'Canvas-owned-custom-parser-only' -and [long]$contract.inputPipeline.parsePasses -eq 1 -and $contract.inputPipeline.parsePassScope -ceq 'exactly-one-parse-pass-per-successfully-decoded-runtime-resource') -Message 'Canvas parser ownership or parse-pass scope changed.'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.runtimeResourceExtensions) -Expected @('.html','.css','.svg') -Description 'Runtime input extensions'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.orderedSteps) -Expected @('acquire-bytes','enforce-byte-limits','strict-decode','select-canvas-parser','parse-once') -Description 'Input pipeline steps'
Assert-ContractExactFields -Value $contract.inputPipeline.parserRoutes -Expected @('html-document','css-stylesheet','svg-document') -Description 'Canvas parser routes'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.forbiddenBackends) -Expected @('Scaleform XML','E4X','XMLList','XMLDocument','parseXML','TextField.htmlText','StyleSheet','StyleSheet.parseCSS') -Description 'Forbidden parser backends'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.forbiddenPurposes) -Expected @('primary-parse','secondary-parse','recovery','validation','conversion') -Description 'Forbidden parser purposes'
Assert-ContractCondition -Condition ([long]$contract.inputPipeline.requiredForbiddenBackendInvocations -eq 0 -and $contract.inputPipeline.secondaryParser -ceq 'none' -and $contract.inputPipeline.recoveryParser -ceq 'none') -Message 'Forbidden-backend or fallback rule changed.'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.observationFields) -Expected @('case','inputs','forbiddenBackendInvocations') -Description 'Pipeline observation fields'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.inputObservationFields) -Expected @('resource','acquisition','decoder','textType','selectedParsers') -Description 'Pipeline input observation fields'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.acquisitionOutcomes) -Expected @('bytes','unavailable') -Description 'Acquisition outcomes'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.decoderOutcomes) -Expected @('strict-utf8-no-bom','not-run','rejected-bom','rejected-invalid-utf8') -Description 'Decoder outcomes'
Assert-ContractExactSequence -Actual @($contract.inputPipeline.textTypes) -Expected @('String','not-created') -Description 'Decoded text types'
Assert-ContractExactSequence -Actual @($contract.terminalResult.stages) -Expected $expectedStages -Description 'Terminal stage order'
Assert-ContractExactSequence -Actual @($contract.failureModel.firstFailureStageOrder) -Expected $expectedStages -Description 'First-failure stage order'
Assert-ContractExactFields -Value $contract.failureModel -Expected @('firstFailureStageOrder','candidateErrorFields','resourceDiscoveryOrder','oneTerminalResult','competingErrorOrder','cleanupErrorPrecedence','recovery','secondaryParser') -Description 'Failure model'
Assert-ContractExactSequence -Actual @($contract.failureModel.candidateErrorFields) -Expected @('stage','code','resource','offset','resourceOrder','limitId') -Description 'Candidate error fields'
Assert-ContractExactSequence -Actual @($contract.failureModel.competingErrorOrder) -Expected @('firstFailureStageOrder-declaration-index','lowest-resourceOrder','non-null-offset-before-null','lowest-nonnegative-offset','terminalResult.codes-declaration-index','limits-declaration-index-for-limit-exceeded','normalized-resource-ordinal','identical-terminal-object-if-all-keys-tie') -Description 'Competing error total order'
Assert-ContractExactSequence -Actual @($contract.terminalResult.codes) -Expected $expectedCodes -Description 'Terminal code vocabulary'
Assert-ContractExactSequence -Actual @($contract.terminalResult.statuses) -Expected $expectedStatuses -Description 'Terminal status vocabulary'
Assert-ContractExactSet -Actual @($contract.terminalResult.codeMeanings.PSObject.Properties.Name) -Expected $expectedCodes -Description 'Terminal code meanings'
Assert-ContractExactSet -Actual @($contract.terminalResult.codeStages.PSObject.Properties.Name) -Expected $expectedCodes -Description 'Terminal code-stage map'
Assert-ContractExactSet -Actual @($contract.elements.standard.PSObject.Properties.Name) -Expected $expectedStandardElements -Description 'Standard element catalog'
Assert-ContractExactSet -Actual @($contract.elements.custom.PSObject.Properties.Name) -Expected $expectedCustomElements -Description 'Custom element catalog'
Assert-ContractExactSequence -Actual @($contract.elements.reservedUnsupported.genericCatalogOrMaskPending) -Expected $expectedReservedGeneric -Description 'Reserved generic elements'
Assert-ContractExactSequence -Actual @($contract.elements.reservedUnsupported.consumerOwned) -Expected $expectedReservedConsumer -Description 'Consumer-owned rejected elements'
Assert-ContractCondition -Condition ($contract.bindings.schema -ceq 'VWCANVAS_HTML_BINDINGS/1') -Message 'Binding schema ID changed.'
Assert-ContractExactSequence -Actual @($contract.bindings.topLevelFields) -Expected @('schema','consumerNamespace','entryDocument','bindings') -Description 'Binding schema fields'
Assert-ContractExactSequence -Actual @($contract.bindings.entryFields) -Expected @('type','default') -Description 'Binding entry fields'
Assert-ContractExactSequence -Actual @($contract.bindings.types) -Expected @('array','boolean','number','string') -Description 'Binding types'
Assert-ContractExactSequence -Actual @($contract.bindings.validationReasons) -Expected @('unknown-top-level-field','wrong-schema','wrong-consumer-association','wrong-entry-document-association','invalid-bindings-shape','invalid-key','unknown-entry-field','unknown-type','wrong-type-default','non-finite-number','array-too-long','nested-array','nested-object','string-too-long') -Description 'Binding validation reasons'
Assert-ContractCondition -Condition ($contract.bindings.runtimeAssetLoading -ceq 'forbidden' -and [long]$contract.bindings.byteBudgetContribution.'source-file-bytes' -eq 0 -and [long]$contract.bindings.byteBudgetContribution.'aggregate-loaded-bytes' -eq 0) -Message 'Out-of-band binding metadata boundary changed.'
Assert-ContractCondition -Condition ($contract.bindings.registrationValidationFailureResource -ceq 'normalized-entry-document-resource') -Message 'Binding validation failure resource changed.'
Assert-ContractExactFields -Value $contract.snapshotUpdates -Expected @('contract','parsedRepresentation','retainedNodeKinds','orderedSteps','snapshotResolution','snapshotValidation','recomposition','previousResourceRule','newResourceRule','newResourceCommit','success','failure','scenarioFields','stepFields','kinds','role') -Description 'Snapshot update contract'
Assert-ContractCondition -Condition ($contract.snapshotUpdates.contract -ceq 'VWCANVAS_HTML_UPDATE/1') -Message 'Snapshot update contract ID changed.'
Assert-ContractExactSequence -Actual @($contract.snapshotUpdates.retainedNodeKinds) -Expected @('active-nodes','inactive-state-children','zero-repeat-source-children','template-children') -Description 'Retained parsed node kinds'
Assert-ContractExactSequence -Actual @($contract.snapshotUpdates.orderedSteps) -Expected @('resolve-snapshot','validate-snapshot','clone-retained-parsed-representation','compose','style','layout','asset','display-bind-render','lifecycle','atomic-commit') -Description 'Snapshot update pipeline'
Assert-ContractExactSequence -Actual @($contract.snapshotUpdates.kinds) -Expected @('state-transition','repeat-transition','newly-activated-asset-failure') -Description 'Snapshot update scenario kinds'
Assert-ContractCondition -Condition ($contract.recipeSchema.schema -ceq 'VWCANVAS_HTML_RECIPE/1') -Message 'Recipe schema ID changed.'
Assert-ContractExactSequence -Actual @($contract.recipeSchema.topLevelFields) -Expected @('schema','stageInput','generator','parameters') -Description 'Recipe fields'
Assert-ContractExactSequence -Actual @($contract.recipeSchema.parameterFields) -Expected @('count') -Description 'Recipe parameter fields'
Assert-ContractExactSet -Actual @($contract.recipeSchema.stageInputDefinitions.PSObject.Properties.Name) -Expected @($contract.recipeSchema.stageInputs) -Description 'Recipe stage-input definitions'
Assert-ContractExactSet -Actual @($contract.recipeSchema.generators.PSObject.Properties.Name) -Expected @($expectedGenerators.Values | ForEach-Object { $_[0] }) -Description 'Recipe generators'
Assert-ContractExactFields -Value $contract.semanticObservationSchema -Expected @('schema','kinds','cssVariableFields','svgDefaultsFields','role') -Description 'Semantic observation schema'
Assert-ContractCondition -Condition ($contract.semanticObservationSchema.schema -ceq 'VWCANVAS_HTML_SEMANTICS/1') -Message 'Semantic observation schema ID changed.'
Assert-ContractExactSequence -Actual @($contract.semanticObservationSchema.kinds) -Expected @('css-variable-resolution','svg-defaults') -Description 'Semantic observation kinds'
Assert-ContractExactSequence -Actual @($contract.semanticObservationSchema.cssVariableFields) -Expected @('case','kind','destinationProperty','destinationGrammar','chain','terminal','resolvedValue','depth','status','code') -Description 'CSS semantic observation fields'
Assert-ContractExactSequence -Actual @($contract.semanticObservationSchema.svgDefaultsFields) -Expected @('case','kind','scope','svg','path') -Description 'SVG semantic observation fields'

$limitById = @{}
foreach ($limit in @($contract.limits)) {
  Assert-ContractExactFields -Value $limit -Expected @('id','stage','value','unit','measurement') -Description "Limit '$($limit.id)'"
  Assert-ContractCondition -Condition (!$limitById.ContainsKey([string]$limit.id)) -Message "Duplicate limit '$($limit.id)'."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $limit.value) -and [long]$limit.value -gt 0) -Message "Limit '$($limit.id)' is not a positive integer."
  Assert-ContractCondition -Condition ($expectedStages -ccontains [string]$limit.stage) -Message "Limit '$($limit.id)' has an unknown stage."
  $limitById.Add([string]$limit.id, $limit)
}
Assert-ContractExactSet -Actual @($limitById.Keys) -Expected @($expectedGenerators.Keys) -Description 'Limit catalog'
foreach ($limitId in $limitById.Keys) {
  $generatorName = [string]$expectedGenerators[$limitId][0]
  $stageInput = [string]$expectedGenerators[$limitId][1]
  $generatorDefinition = $contract.recipeSchema.generators.$generatorName
  Assert-ContractCondition -Condition ($generatorDefinition.metric -ceq $limitId -and $generatorDefinition.stageInput -ceq $stageInput) -Message "Generator '$generatorName' is not bound to '$limitId' and '$stageInput'."
}

Assert-ContractExactFields -Value $corpus -Expected @('schema','contract','contractPath','contractCanonicalSha256','runtimeImplemented','inputPipeline','recipeSchema','bindingSchema','snapshotUpdateContract','categories','resourceKinds','resourceSources','evidenceKinds','specAssertions','bindingMetadata','pipelineObservations','semanticObservations','cases','snapshotUpdateScenarios','scenarios') -Description 'Corpus'
Assert-ContractCondition -Condition ($corpus.schema -ceq 'VWCANVAS_HTML_CORPUS/1' -and $corpus.contract -ceq $expectedContract) -Message 'Corpus identity changed.'
Assert-ContractCondition -Condition ($corpus.contractCanonicalSha256 -ceq $expectedContractDigest) -Message 'Corpus contract digest changed.'
Assert-ContractCondition -Condition ($corpus.runtimeImplemented -eq $false) -Message 'Corpus claims runtime execution.'
Assert-ContractCondition -Condition ($corpus.inputPipeline -ceq 'VWCANVAS_HTML_INPUT/1' -and $corpus.recipeSchema -ceq 'VWCANVAS_HTML_RECIPE/1' -and $corpus.bindingSchema -ceq 'VWCANVAS_HTML_BINDINGS/1' -and $corpus.snapshotUpdateContract -ceq 'VWCANVAS_HTML_UPDATE/1') -Message 'Corpus schema associations changed.'
Assert-ContractExactSequence -Actual @($corpus.categories) -Expected $expectedCategories -Description 'Corpus categories'
Assert-ContractExactSequence -Actual @($corpus.resourceKinds) -Expected $expectedResourceKinds -Description 'Corpus resource kinds'
Assert-ContractExactSequence -Actual @($corpus.resourceSources) -Expected $expectedResourceSources -Description 'Corpus resource sources'
Assert-ContractExactSequence -Actual @($corpus.evidenceKinds) -Expected $expectedEvidenceKinds -Description 'Corpus evidence kinds'
Assert-ContractExactSequence -Actual @($corpus.specAssertions) -Expected $expectedSpecAssertions -Description 'Corpus spec assertions'
$resolvedCorpusContract = [IO.Path]::GetFullPath((Join-Path $corpusRoot $corpus.contractPath))
Assert-ContractCondition -Condition ($resolvedCorpusContract -ceq [IO.Path]::GetFullPath($contractPath)) -Message 'Corpus contract path does not resolve to the manifest.'

$caseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$resourceNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$indexedFilePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$allLogicalPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$categoryCounts = @{}
$probeCounts = @{}
$specCounts = @{}
$bindingMetadataByName = @{}
$activeBindingNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$caseResourcesByCase = @{}
$caseById = @{}
foreach ($category in $expectedCategories) { $categoryCounts[$category] = 0 }
foreach ($limitId in $limitById.Keys) { $probeCounts[$limitId] = @{ at = 0; over = 0 } }
foreach ($assertion in $expectedSpecAssertions) { $specCounts[$assertion] = 0 }

Assert-ContractCondition -Condition ($contract.assets.jsonRuntimeResource -ceq 'forbidden-invalid-path' -and @($contract.assets.extensions) -cnotcontains '.json') -Message 'JSON became a runtime resource or asset extension.'
foreach ($metadata in @($corpus.bindingMetadata)) {
  Assert-ContractExactFields -Value $metadata -Expected @('name','case','path','expectedCanonicalUtf8Bytes','expectedCanonicalCodeUnits','canonicalSha256') -Description "Binding metadata '$($metadata.name)'"
  $metadataName = [string]$metadata.name
  $metadataPath = [string]$metadata.path
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace($metadataName) -and $resourceNames.Add($metadataName)) -Message "Duplicate or empty binding metadata name '$metadataName'."
  Assert-ContractCondition -Condition ($metadataPath -cnotmatch '\\' -and $metadataPath -ceq $metadataPath.ToLowerInvariant() -and $metadataPath.EndsWith('.json', [StringComparison]::Ordinal)) -Message "Binding metadata '$metadataName' path is not a normalized JSON corpus path."
  Assert-ContractCondition -Condition (![IO.Path]::IsPathRooted($metadataPath) -and $metadataPath -cnotmatch '(^|/)\.\.?(/|$)') -Message "Binding metadata '$metadataName' path is unsafe."
  Assert-ContractCondition -Condition $allLogicalPaths.Add($metadataPath) -Message "Logical metadata path '$metadataPath' is indexed more than once."
  $metadataFullPath = [IO.Path]::GetFullPath((Join-Path $corpusRoot $metadataPath))
  Assert-ContractCondition -Condition $metadataFullPath.StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -Message "Binding metadata '$metadataName' escapes the fixture root."
  Assert-ContractCondition -Condition (Test-Path -LiteralPath $metadataFullPath -PathType Leaf) -Message "Binding metadata '$metadataName' is missing."
  Assert-ContractCondition -Condition $indexedFilePaths.Add($metadataPath) -Message "Binding metadata '$metadataPath' is indexed more than once."
  $metadataInfo = Get-ContractCanonicalTextInfo -Path $metadataFullPath -Description "Binding metadata '$metadataName'"
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $metadata.expectedCanonicalUtf8Bytes) -and [long]$metadata.expectedCanonicalUtf8Bytes -eq $metadataInfo.CanonicalBytes.LongLength) -Message "Binding metadata '$metadataName' canonical byte count changed."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $metadata.expectedCanonicalCodeUnits) -and [long]$metadata.expectedCanonicalCodeUnits -eq $metadataInfo.CanonicalText.Length) -Message "Binding metadata '$metadataName' canonical code-unit count changed."
  Assert-ContractCondition -Condition ([string]$metadata.canonicalSha256 -cmatch '^[0-9a-f]{64}$' -and [string]$metadata.canonicalSha256 -ceq $metadataInfo.CanonicalSha256) -Message "Binding metadata '$metadataName' canonical SHA-256 changed."
  $bindingMetadataByName[$metadataName] = [pscustomobject]@{ Definition = $metadata; Schema = ($metadataInfo.CanonicalText | ConvertFrom-Json -Depth 30) }
}

foreach ($case in @($corpus.cases)) {
  $caseId = [string]$case.id
  $category = [string]$case.category
  $caseFields = [Collections.Generic.List[string]]::new()
  @('id','category','entry','evidence','activeBindingSchema','resources','expected') | ForEach-Object { $caseFields.Add($_) }
  foreach ($optionalField in @('consumerNamespace','bindingExpectation','limitProbe','trigger','specAssertion')) {
    if ($case.PSObject.Properties.Name -ccontains $optionalField) { $caseFields.Add($optionalField) }
  }
  Assert-ContractExactFields -Value $case -Expected $caseFields.ToArray() -Description "Case '$caseId'"
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace($caseId)) -Message 'A corpus case has no ID.'
  Assert-ContractCondition -Condition $caseIds.Add($caseId) -Message "Duplicate case '$caseId'."
  $caseById[$caseId] = $case
  Assert-ContractCondition -Condition ($expectedCategories -ccontains $category) -Message "Case '$caseId' has unknown category '$category'."
  Assert-ContractCondition -Condition ($expectedEvidenceKinds -ccontains [string]$case.evidence) -Message "Case '$caseId' has unknown evidence '$($case.evidence)'."
  $categoryCounts[$category]++

  $caseResourceNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $caseResourceTexts = @{}
  $caseResourcesByName = @{}
  foreach ($resource in @($case.resources)) {
    $resourceName = [string]$resource.name
    $relativePath = [string]$resource.path
    Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace($resourceName)) -Message "Case '$caseId' has an unnamed resource."
    Assert-ContractCondition -Condition $resourceNames.Add($resourceName) -Message "Duplicate resource name '$resourceName'."
    Assert-ContractCondition -Condition $caseResourceNames.Add($resourceName) -Message "Case '$caseId' repeats resource '$resourceName'."
    Assert-ContractCondition -Condition ($expectedResourceKinds -ccontains [string]$resource.kind) -Message "Resource '$resourceName' has unknown kind '$($resource.kind)'."
    Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace($relativePath)) -Message "Resource '$resourceName' has no path."
    Assert-ContractCondition -Condition ($relativePath -cnotmatch '\\' -and $relativePath -ceq $relativePath.ToLowerInvariant()) -Message "Resource '$resourceName' path is not normalized lower-case with forward slashes."
    Assert-ContractCondition -Condition $relativePath.StartsWith("fixtures/$category/", [StringComparison]::Ordinal) -Message "Resource '$resourceName' is outside its category."
    Assert-ContractCondition -Condition (![IO.Path]::IsPathRooted($relativePath)) -Message "Resource '$resourceName' path is rooted."
    Assert-ContractCondition -Condition ($relativePath -cnotmatch '(^|/)\.\.?(/|$)') -Message "Resource '$resourceName' path contains a dot segment."
    Assert-ContractCondition -Condition $allLogicalPaths.Add($relativePath) -Message "Logical resource path '$relativePath' is indexed more than once."
    $caseResourcesByName[$resourceName] = $resource

    $fullPath = [IO.Path]::GetFullPath((Join-Path $corpusRoot $relativePath))
    Assert-ContractCondition -Condition $fullPath.StartsWith($fixtureRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -Message "Resource '$resourceName' escapes the fixture root."

    if ([string]$resource.kind -ceq 'recipe') {
      Assert-ContractExactFields -Value $resource -Expected @('name','kind','path') -Description "Recipe resource '$resourceName'"
      Assert-ContractCondition -Condition ([string]$case.evidence -ceq 'declarative-recipe') -Message "Recipe '$resourceName' has the wrong evidence kind."
      Assert-ContractCondition -Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) -Message "Recipe '$resourceName' is missing."
      Assert-ContractCondition -Condition $indexedFilePaths.Add($relativePath) -Message "Recipe '$relativePath' is indexed more than once."
      $recipeInfo = Get-ContractCanonicalTextInfo -Path $fullPath -Description "Recipe '$resourceName'"
      $recipe = $recipeInfo.Text | ConvertFrom-Json -Depth 20
      Assert-ContractExactFields -Value $recipe -Expected @('schema','stageInput','generator','parameters') -Description "Recipe '$resourceName'"
      Assert-ContractExactFields -Value $recipe.parameters -Expected @('count') -Description "Recipe '$resourceName' parameters"
      Assert-ContractCondition -Condition ($recipe.schema -ceq 'VWCANVAS_HTML_RECIPE/1') -Message "Recipe '$resourceName' has the wrong schema."
      Assert-ContractCondition -Condition ((Test-ContractInteger -Value $recipe.parameters.count) -and [long]$recipe.parameters.count -ge 0 -and [long]$recipe.parameters.count -le 600000) -Message "Recipe '$resourceName' count is outside its bounded integer domain."
      Assert-ContractCondition -Condition ($case.PSObject.Properties.Name -ccontains 'limitProbe') -Message "Recipe case '$caseId' has no limit probe."
      Assert-ContractExactFields -Value $case.limitProbe -Expected @('id','position') -Description "Case '$caseId' limit probe"
      $limitId = [string]$case.limitProbe.id
      $position = [string]$case.limitProbe.position
      Assert-ContractCondition -Condition $limitById.ContainsKey($limitId) -Message "Case '$caseId' probes unknown limit '$limitId'."
      Assert-ContractCondition -Condition (@('at','over') -ccontains $position) -Message "Case '$caseId' has invalid probe position '$position'."
      $generatorName = [string]$expectedGenerators[$limitId][0]
      $stageInput = [string]$expectedGenerators[$limitId][1]
      Assert-ContractCondition -Condition ($recipe.generator -ceq $generatorName -and $recipe.stageInput -ceq $stageInput) -Message "Recipe '$resourceName' does not use the exact generator and stage input for '$limitId'."
      $expectedCount = [long]$limitById[$limitId].value + $(if ($position -ceq 'over') { 1 } else { 0 })
      Assert-ContractCondition -Condition ([long]$recipe.parameters.count -eq $expectedCount) -Message "Recipe '$resourceName' count must be $expectedCount."
      $measurements = Invoke-ContractRecipeGenerator -Recipe $recipe -LimitById $limitById
      Assert-ContractCondition -Condition ([long]$measurements[$limitId] -eq $expectedCount) -Message "Generator '$generatorName' did not independently derive its target measurement."
      foreach ($companion in @($requiredRecipeCompanions[$generatorName])) {
        Assert-ContractCondition -Condition ([long]$measurements[$companion] -gt 0) -Message "Generator '$generatorName' omitted required companion '$companion'."
      }
      $violations = @($limitById.Keys | Where-Object { [long]$measurements[$_] -gt [long]$limitById[$_].value })
      if ($position -ceq 'at') {
        Assert-ContractCondition -Condition ($violations.Count -eq 0) -Message "At-limit recipe '$resourceName' violates: $($violations -join ', ')."
      }
      else {
        Assert-ContractExactSequence -Actual $violations -Expected @($limitId) -Description "Over-limit recipe '$resourceName' isolated violation"
      }
      $probeCounts[$limitId][$position]++
      continue
    }

    $source = [string]$resource.source
    Assert-ContractCondition -Condition ($expectedResourceSources -ccontains $source) -Message "Resource '$resourceName' has unknown source '$source'."
    switch ($source) {
      'file' {
        Assert-ContractExactFields -Value $resource -Expected @('name','kind','source','path','expectedCanonicalUtf8Bytes','expectedCanonicalCodeUnits','canonicalSha256') -Description "Physical resource '$resourceName'"
        Assert-ContractCondition -Condition ([string]$case.evidence -ceq 'physical') -Message "File resource '$resourceName' is not physical evidence."
        Assert-ContractCondition -Condition (Test-Path -LiteralPath $fullPath -PathType Leaf) -Message "Physical resource '$resourceName' is missing."
        Assert-ContractCondition -Condition $indexedFilePaths.Add($relativePath) -Message "Physical path '$relativePath' is indexed more than once."
        $resourceInfo = Get-ContractCanonicalTextInfo -Path $fullPath -Description "Physical resource '$resourceName'"
        Assert-ContractCondition -Condition ((Test-ContractInteger -Value $resource.expectedCanonicalUtf8Bytes) -and [long]$resource.expectedCanonicalUtf8Bytes -eq $resourceInfo.CanonicalBytes.LongLength) -Message "Physical resource '$resourceName' canonical byte count changed."
        Assert-ContractCondition -Condition ((Test-ContractInteger -Value $resource.expectedCanonicalCodeUnits) -and [long]$resource.expectedCanonicalCodeUnits -eq $resourceInfo.CanonicalText.Length) -Message "Physical resource '$resourceName' canonical code-unit count changed."
        Assert-ContractCondition -Condition ([string]$resource.canonicalSha256 -cmatch '^[0-9a-f]{64}$' -and $resource.canonicalSha256 -ceq $resourceInfo.CanonicalSha256) -Message "Physical resource '$resourceName' canonical SHA-256 changed."
        $caseResourceTexts[$resourceName] = $resourceInfo.CanonicalText
      }
      'absent' {
        Assert-ContractExactFields -Value $resource -Expected @('name','kind','source','path') -Description "Absent resource '$resourceName'"
        Assert-ContractCondition -Condition ([string]$case.evidence -ceq 'modeled-resource') -Message "Absent resource '$resourceName' is not modeled evidence."
        Assert-ContractCondition -Condition (!(Test-Path -LiteralPath $fullPath)) -Message "Deliberately absent resource '$resourceName' exists on disk."
      }
      'base64' {
        Assert-ContractExactFields -Value $resource -Expected @('name','kind','source','path','payloadBase64','rawSha256') -Description "Raw resource '$resourceName'"
        Assert-ContractCondition -Condition ([string]$case.evidence -ceq 'modeled-resource') -Message "Raw resource '$resourceName' is not modeled evidence."
        Assert-ContractCondition -Condition (!(Test-Path -LiteralPath $fullPath)) -Message "Raw modeled resource '$resourceName' unexpectedly exists on disk."
        try { $rawBytes = [Convert]::FromBase64String([string]$resource.payloadBase64) } catch { throw "Raw resource '$resourceName' has invalid base64." }
        Assert-ContractCondition -Condition ([Convert]::ToBase64String($rawBytes) -ceq [string]$resource.payloadBase64) -Message "Raw resource '$resourceName' base64 is not canonical."
        Assert-ContractCondition -Condition ([string]$resource.rawSha256 -cmatch '^[0-9a-f]{64}$' -and [string]$resource.rawSha256 -ceq (Get-ContractSha256 -Bytes $rawBytes)) -Message "Raw resource '$resourceName' SHA-256 changed."
        $hasBom = $rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF
        $invalidUtf8 = $false
        try { $null = [Text.UTF8Encoding]::new($false, $true).GetString($rawBytes) } catch [Text.DecoderFallbackException] { $invalidUtf8 = $true }
        Assert-ContractCondition -Condition ($hasBom -or $invalidUtf8) -Message "Raw invalid-encoding resource '$resourceName' is valid BOM-free UTF-8."
      }
    }
  }

  $caseResourcesByCase[$caseId] = $caseResourcesByName

  Assert-ContractCondition -Condition $caseResourceNames.Contains([string]$case.entry) -Message "Case '$caseId' entry is not one of its resources."
  Assert-ContractCondition -Condition ($null -ne $case.expected -and $case.expected -isnot [object[]]) -Message "Case '$caseId' does not have exactly one expected object."
  Assert-ContractTerminalResult -Result $case.expected -Description "Case '$caseId' result" -ContractId $expectedContract -Stages $expectedStages -Codes $expectedCodes -CodeStages $contract.terminalResult.codeStages -LimitById $limitById
  $expectedResourceName = [string]$case.expected.resource
  Assert-ContractCondition -Condition $caseResourceNames.Contains($expectedResourceName) -Message "Case '$caseId' result references an unknown runtime resource."
  if ($case.PSObject.Properties.Name -ccontains 'limitProbe') {
    $probedLimit = $limitById[[string]$case.limitProbe.id]
    if ([string]$case.limitProbe.position -ceq 'at') {
      Assert-ContractCondition -Condition ([string]$case.expected.contract -ceq $expectedContract -and [string]$case.expected.status -ceq 'accepted' -and [string]$case.expected.stage -ceq 'lifecycle' -and $null -eq $case.expected.code -and [string]$case.expected.resource -ceq [string]$case.entry -and $null -eq $case.expected.offset -and $null -eq $case.expected.limitId -and $case.expected.committed -eq $true) -Message "At-limit case '$caseId' is not bound to the exact accepted terminal result."
    }
    else {
      Assert-ContractCondition -Condition ([string]$case.expected.contract -ceq $expectedContract -and [string]$case.expected.status -ceq 'rejected' -and [string]$case.expected.stage -ceq [string]$probedLimit.stage -and [string]$case.expected.code -ceq 'limit-exceeded' -and [string]$case.expected.resource -ceq [string]$case.entry -and $null -eq $case.expected.offset -and [string]$case.expected.limitId -ceq [string]$probedLimit.id -and $case.expected.committed -eq $false) -Message "Over-limit case '$caseId' is not bound to the exact rejected terminal result."
    }
  }

  if ([string]$case.evidence -ceq 'modeled-resource') {
    $entryResource = $caseResourcesByName[[string]$case.entry]
    if ([string]$entryResource.source -ceq 'absent') {
      Assert-ContractCondition -Condition ([string]$case.expected.status -ceq 'rejected' -and [string]$case.expected.stage -ceq 'load' -and [string]$case.expected.code -ceq 'resource-unavailable' -and $null -eq $case.expected.offset) -Message "Absent case '$caseId' has the wrong result."
    }
    else {
      Assert-ContractCondition -Condition ([string]$case.expected.status -ceq 'rejected' -and [string]$case.expected.stage -ceq 'load' -and [string]$case.expected.code -ceq 'invalid-encoding' -and [long]$case.expected.offset -eq 0) -Message "Raw encoding case '$caseId' has the wrong result."
    }
  }

  if ($case.PSObject.Properties.Name -ccontains 'trigger') {
    Assert-ContractExactFields -Value $case.trigger -Expected @('resource','marker') -Description "Case '$caseId' trigger"
    $triggerResource = [string]$case.trigger.resource
    $triggerMarker = [string]$case.trigger.marker
    Assert-ContractCondition -Condition $caseResourceTexts.ContainsKey($triggerResource) -Message "Case '$caseId' trigger resource has no physical text."
    Assert-ContractCondition -Condition (![string]::IsNullOrEmpty($triggerMarker)) -Message "Case '$caseId' trigger marker is empty."
    $triggerText = [string]$caseResourceTexts[$triggerResource]
    $triggerIndex = $triggerText.IndexOf($triggerMarker, [StringComparison]::Ordinal)
    Assert-ContractCondition -Condition ($triggerIndex -ge 0 -and $triggerIndex -eq $triggerText.LastIndexOf($triggerMarker, [StringComparison]::Ordinal)) -Message "Case '$caseId' trigger is missing or not unique."
    $triggerOffset = [Text.UTF8Encoding]::new($false).GetByteCount($triggerText.Substring(0, $triggerIndex))
    Assert-ContractCondition -Condition ([string]$case.expected.resource -ceq $triggerResource -and [long]$case.expected.offset -eq $triggerOffset) -Message "Case '$caseId' trigger result location changed."
  }

  if ($case.PSObject.Properties.Name -ccontains 'specAssertion') {
    $assertion = [string]$case.specAssertion
    Assert-ContractCondition -Condition ($expectedSpecAssertions -ccontains $assertion) -Message "Case '$caseId' has unknown spec assertion '$assertion'."
    $specCounts[$assertion]++
    switch ($assertion) {
      'css-variable-valid-substitution' { Assert-ContractCondition -Condition (@($caseResourceTexts.Values | Where-Object { $_.Contains('--tone:#ffffff; color:var(--tone);', [StringComparison]::Ordinal) }).Count -eq 1 -and [string]$case.expected.status -ceq 'accepted') -Message "Spec assertion '$assertion' changed." }
      'css-variable-missing' { Assert-ContractCondition -Condition ([string]$case.expected.stage -ceq 'style' -and [string]$case.expected.code -ceq 'unresolved-reference') -Message "Spec assertion '$assertion' changed." }
      'css-variable-terminal-type-mismatch' { Assert-ContractCondition -Condition ([string]$case.expected.stage -ceq 'style' -and [string]$case.expected.code -ceq 'invalid-value') -Message "Spec assertion '$assertion' changed." }
      'css-variable-cycle' { Assert-ContractCondition -Condition ([string]$case.expected.stage -ceq 'style' -and [string]$case.expected.code -ceq 'cycle') -Message "Spec assertion '$assertion' changed." }
      'css-variable-depth-at-limit' { $css = [string](@($caseResourceTexts.Values | Where-Object { $_ -cmatch 'var\(' })[0]); Assert-ContractCondition -Condition (([regex]::Matches($css, 'var\(').Count -eq 16) -and [string]$case.expected.status -ceq 'accepted') -Message "Spec assertion '$assertion' changed." }
      'css-variable-depth-over-limit' { $css = [string](@($caseResourceTexts.Values | Where-Object { $_ -cmatch 'var\(' })[0]); Assert-ContractCondition -Condition (([regex]::Matches($css, 'var\(').Count -eq 17) -and [string]$case.expected.code -ceq 'limit-exceeded' -and [string]$case.expected.limitId -ceq 'variable-depth') -Message "Spec assertion '$assertion' changed." }
      'standalone-svg-external' { $svg = [string](@($caseResourceTexts.Values | Where-Object { $_ -cmatch '^<svg ' })[0]); Assert-ContractCondition -Condition ($svg.StartsWith('<svg viewbox=', [StringComparison]::Ordinal) -and !$svg.Contains('<!doctype', [StringComparison]::Ordinal) -and [string]$case.expected.status -ceq 'accepted') -Message "Spec assertion '$assertion' changed." }
      'svg-omitted-defaults' { $document = [string](@($caseResourceTexts.Values | Where-Object { $_ -cmatch '<svg viewbox=' })[0]); Assert-ContractCondition -Condition ($document.Contains('<svg viewbox="0 0 18 18"><path d=', [StringComparison]::Ordinal) -and $document -cnotmatch 'preserveaspectratio=|fill-rule=|clip-rule=|stroke-linecap=|stroke-linejoin=|vector-effect=| x=| y=' -and [string]$case.expected.status -ceq 'accepted') -Message "Spec assertion '$assertion' changed." }
    }
  }

  $activeBindingName = [string]$case.activeBindingSchema
  if ([string]::IsNullOrEmpty($activeBindingName)) {
    Assert-ContractCondition -Condition ($case.PSObject.Properties.Name -cnotcontains 'bindingExpectation') -Message "Case '$caseId' has a binding expectation without active metadata."
  }
  else {
    Assert-ContractCondition -Condition $bindingMetadataByName.ContainsKey($activeBindingName) -Message "Case '$caseId' names unknown out-of-band binding metadata."
    Assert-ContractCondition -Condition $activeBindingNames.Add($activeBindingName) -Message "Binding metadata '$activeBindingName' is active in more than one case."
    $bindingRecord = $bindingMetadataByName[$activeBindingName]
    Assert-ContractCondition -Condition ([string]$bindingRecord.Definition.case -ceq $caseId) -Message "Binding metadata '$activeBindingName' is registered for the wrong corpus case."
    Assert-ContractCondition -Condition ($case.PSObject.Properties.Name -ccontains 'consumerNamespace') -Message "Case '$caseId' has no consumer namespace for its active bindings."
    Assert-ContractCondition -Condition ($case.PSObject.Properties.Name -ccontains 'bindingExpectation') -Message "Case '$caseId' has no binding validation expectation."
    Assert-ContractExactFields -Value $case.bindingExpectation -Expected @('status','reason','key') -Description "Case '$caseId' binding expectation"
    $bindingSchema = $bindingRecord.Schema
    $entryResource = $caseResourcesByName[[string]$case.entry]
    $bindingValidation = Get-ContractBindingValidation -Schema $bindingSchema -ConsumerNamespace ([string]$case.consumerNamespace) -EntryDocument ([IO.Path]::GetFileName([string]$entryResource.path)) -LimitById $limitById
    foreach ($field in @('status','reason','key')) {
      Assert-ContractCondition -Condition ([string]$bindingValidation.$field -ceq [string]$case.bindingExpectation.$field) -Message "Case '$caseId' binding $field changed."
    }
    if ([string]$bindingValidation.status -ceq 'accepted') {
      Assert-ContractCondition -Condition ([string]$case.expected.status -ceq 'accepted') -Message "Case '$caseId' accepts bindings but has a rejected terminal result."
      if ($caseId -ceq 'valid.bindings-all-types') {
        $bindingTypes = @($bindingSchema.bindings.PSObject.Properties.Value.type)
        Assert-ContractCondition -Condition ($bindingTypes.Count -eq 5 -and @($bindingTypes | Where-Object { $_ -ceq 'array' }).Count -eq 1 -and @($bindingTypes | Where-Object { $_ -ceq 'boolean' }).Count -eq 2 -and @($bindingTypes | Where-Object { $_ -ceq 'number' }).Count -eq 1 -and @($bindingTypes | Where-Object { $_ -ceq 'string' }).Count -eq 1) -Message 'All-types binding fixture no longer exercises every binding type.'
        $arrayDefault = @($bindingSchema.bindings.items.default)
        Assert-ContractCondition -Condition ($arrayDefault.Count -eq 4 -and $null -eq $arrayDefault[0] -and $arrayDefault[1] -is [bool] -and (Test-ContractFiniteNumber -Value $arrayDefault[2]) -and $arrayDefault[3] -is [string]) -Message 'All-types binding fixture no longer exercises every allowed array scalar branch.'
      }
      $entryText = [string]$caseResourceTexts[[string]$case.entry]
      $bindingSites = @(
        @{Pattern='data-vw-text="([^"]+)"';Type='string'}, @{Pattern='data-vw-visible="([^"]+)"';Type='boolean'}, @{Pattern='<vw-state when="([^"]+)"';Type='boolean'},
        @{Pattern='<vw-repeat items="([^"]+)"';Type='array'}, @{Pattern='<vw-meter value="([^"]+)"';Type='number'}
      )
      foreach ($site in $bindingSites) {
        foreach ($match in [regex]::Matches($entryText, [string]$site.Pattern)) {
          $key = $match.Groups[1].Value
          $bindingProperty = $bindingSchema.bindings.PSObject.Properties[$key]
          Assert-ContractCondition -Condition ($null -ne $bindingProperty) -Message "Entry document references undeclared binding '$key'."
          Assert-ContractCondition -Condition ([string]$bindingProperty.Value.type -ceq [string]$site.Type) -Message "Entry document binding '$key' has the wrong declared type."
        }
      }
    }
    else {
      Assert-ContractCondition -Condition ([string]$case.expected.status -ceq 'rejected' -and [string]$case.expected.stage -ceq 'bind' -and [string]$case.expected.code -ceq 'invalid-value' -and [string]$case.expected.resource -ceq [string]$case.entry -and $null -eq $case.expected.offset -and $null -eq $case.expected.limitId -and $case.expected.committed -eq $false) -Message "Case '$caseId' binding rejection terminal changed."
    }
  }
}

foreach ($category in $expectedCategories) {
  Assert-ContractCondition -Condition ($categoryCounts[$category] -gt 0) -Message "Corpus category '$category' has no cases."
}
foreach ($limitId in $limitById.Keys) {
  Assert-ContractCondition -Condition ($probeCounts[$limitId].at -eq 1 -and $probeCounts[$limitId].over -eq 1) -Message "Limit '$limitId' does not have exactly one at/over recipe pair."
}
foreach ($assertion in $expectedSpecAssertions) {
  Assert-ContractCondition -Condition ($specCounts[$assertion] -eq 1) -Message "Spec assertion '$assertion' does not have exactly one case."
}
Assert-ContractExactSet -Actual @($activeBindingNames) -Expected @($bindingMetadataByName.Keys) -Description 'Active out-of-band binding metadata'

$expectedPipelineObservations = @{
  'valid.external-svg' = @{
    'valid-external-svg-document' = [pscustomobject]@{ Acquisition='bytes'; Decoder='strict-utf8-no-bom'; TextType='String'; Parsers=@('canvas-html-document-parser') }
    'valid-external-svg-stylesheet' = [pscustomobject]@{ Acquisition='bytes'; Decoder='strict-utf8-no-bom'; TextType='String'; Parsers=@('canvas-css-parser') }
    'valid-external-svg-asset' = [pscustomobject]@{ Acquisition='bytes'; Decoder='strict-utf8-no-bom'; TextType='String'; Parsers=@('canvas-svg-parser') }
  }
  'valid.template-clone' = @{
    'valid-template-clone-document' = [pscustomobject]@{ Acquisition='bytes'; Decoder='strict-utf8-no-bom'; TextType='String'; Parsers=@('canvas-html-document-parser') }
  }
  'hostile.resource-unavailable' = @{ 'hostile-unavailable-document' = [pscustomobject]@{ Acquisition='unavailable'; Decoder='not-run'; TextType='not-created'; Parsers=@() } }
  'hostile.utf8-bom' = @{ 'hostile-utf8-bom-document' = [pscustomobject]@{ Acquisition='bytes'; Decoder='rejected-bom'; TextType='not-created'; Parsers=@() } }
  'hostile.invalid-utf8' = @{ 'hostile-invalid-utf8-document' = [pscustomobject]@{ Acquisition='bytes'; Decoder='rejected-invalid-utf8'; TextType='not-created'; Parsers=@() } }
}
$pipelineCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$allowedParsers = @($contract.inputPipeline.parserRoutes.PSObject.Properties.Value)
foreach ($observation in @($corpus.pipelineObservations)) {
  Assert-ContractExactFields -Value $observation -Expected @($contract.inputPipeline.observationFields) -Description "Pipeline observation '$($observation.case)'"
  $observationCase = [string]$observation.case
  Assert-ContractCondition -Condition ($pipelineCases.Add($observationCase) -and $expectedPipelineObservations.ContainsKey($observationCase) -and $caseById.ContainsKey($observationCase)) -Message "Unknown or duplicate pipeline observation '$observationCase'."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $observation.forbiddenBackendInvocations) -and [long]$observation.forbiddenBackendInvocations -eq [long]$contract.inputPipeline.requiredForbiddenBackendInvocations) -Message "Pipeline observation '$observationCase' invoked a forbidden backend."
  $observedInputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($inputObservation in @($observation.inputs)) {
    Assert-ContractExactFields -Value $inputObservation -Expected @($contract.inputPipeline.inputObservationFields) -Description "Pipeline input '$($inputObservation.resource)'"
    $observedResource = [string]$inputObservation.resource
    Assert-ContractCondition -Condition ($observedInputs.Add($observedResource) -and $expectedPipelineObservations[$observationCase].ContainsKey($observedResource) -and $caseResourcesByCase[$observationCase].ContainsKey($observedResource)) -Message "Pipeline observation '$observationCase' has an unknown or duplicate resource '$observedResource'."
    $expectedInput = $expectedPipelineObservations[$observationCase][$observedResource]
    Assert-ContractCondition -Condition ([string]$inputObservation.acquisition -ceq [string]$expectedInput.Acquisition -and [string]$inputObservation.decoder -ceq [string]$expectedInput.Decoder -and [string]$inputObservation.textType -ceq [string]$expectedInput.TextType) -Message "Pipeline observation '$observationCase/$observedResource' route state changed."
    Assert-ContractExactSequence -Actual @($inputObservation.selectedParsers) -Expected @($expectedInput.Parsers) -Description "Pipeline observation '$observationCase/$observedResource' parsers"
    Assert-ContractCondition -Condition (@($inputObservation.selectedParsers).Count -le 1) -Message "Pipeline observation '$observationCase/$observedResource' reparses one decoded resource."
    foreach ($parser in @($inputObservation.selectedParsers)) {
      Assert-ContractCondition -Condition ($allowedParsers -ccontains [string]$parser -and @($contract.inputPipeline.forbiddenBackends) -cnotcontains [string]$parser) -Message "Pipeline observation '$observationCase/$observedResource' selected an unowned parser."
    }
  }
  Assert-ContractExactSet -Actual @($observedInputs) -Expected @($expectedPipelineObservations[$observationCase].Keys) -Description "Pipeline observation '$observationCase' inputs"
}
Assert-ContractExactSet -Actual @($pipelineCases) -Expected @($expectedPipelineObservations.Keys) -Description 'Pipeline observation cases'

$expectedCssSemantics = @{
  'valid.css-variable-substitution' = [pscustomobject]@{ Chain=@('--tone'); Terminal='#ffffff'; Resolved='#ffffff'; Depth=1; Status='accepted'; Code=$null }
  'hostile.css-variable-missing' = [pscustomobject]@{ Chain=@('--missing'); Terminal=$null; Resolved=$null; Depth=1; Status='rejected'; Code='unresolved-reference' }
  'hostile.css-variable-terminal-type-mismatch' = [pscustomobject]@{ Chain=@('--size'); Terminal='18px'; Resolved=$null; Depth=1; Status='rejected'; Code='invalid-value' }
  'cycle.css-variable' = [pscustomobject]@{ Chain=@('--a','--b','--a'); Terminal=$null; Resolved=$null; Depth=3; Status='rejected'; Code='cycle' }
  'boundary.css-variable-depth-physical.at' = [pscustomobject]@{ Chain=@('--v01','--v02','--v03','--v04','--v05','--v06','--v07','--v08','--v09','--v10','--v11','--v12','--v13','--v14','--v15','--v16'); Terminal='#ffffff'; Resolved='#ffffff'; Depth=16; Status='accepted'; Code=$null }
  'exhaustion.css-variable-depth-physical.over' = [pscustomobject]@{ Chain=@('--v01','--v02','--v03','--v04','--v05','--v06','--v07','--v08','--v09','--v10','--v11','--v12','--v13','--v14','--v15','--v16','--v17'); Terminal='#ffffff'; Resolved=$null; Depth=17; Status='rejected'; Code='limit-exceeded' }
}
$semanticCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($observation in @($corpus.semanticObservations)) {
  $observationCase = [string]$observation.case
  Assert-ContractCondition -Condition ($semanticCases.Add($observationCase) -and $caseById.ContainsKey($observationCase)) -Message "Unknown or duplicate semantic observation '$observationCase'."
  if ([string]$observation.kind -ceq 'css-variable-resolution') {
    Assert-ContractExactFields -Value $observation -Expected @($contract.semanticObservationSchema.cssVariableFields) -Description "CSS semantic observation '$observationCase'"
    Assert-ContractCondition -Condition $expectedCssSemantics.ContainsKey($observationCase) -Message "Unexpected CSS semantic observation '$observationCase'."
    $expectedSemantic = $expectedCssSemantics[$observationCase]
    Assert-ContractCondition -Condition ([string]$observation.destinationProperty -ceq 'color' -and [string]$observation.destinationGrammar -ceq [string]$contract.css.properties.color) -Message "CSS semantic observation '$observationCase' destination grammar changed."
    Assert-ContractExactSequence -Actual @($observation.chain) -Expected @($expectedSemantic.Chain) -Description "CSS semantic observation '$observationCase' chain"
    Assert-ContractCondition -Condition ([string]$observation.terminal -ceq [string]$expectedSemantic.Terminal -and [string]$observation.resolvedValue -ceq [string]$expectedSemantic.Resolved -and [long]$observation.depth -eq [long]$expectedSemantic.Depth -and [string]$observation.status -ceq [string]$expectedSemantic.Status -and [string]$observation.code -ceq [string]$expectedSemantic.Code) -Message "CSS semantic observation '$observationCase' values changed."
    Assert-ContractCondition -Condition ([string]$observation.status -ceq [string]$caseById[$observationCase].expected.status -and [string]$observation.code -ceq [string]$caseById[$observationCase].expected.code) -Message "CSS semantic observation '$observationCase' disagrees with its terminal result."
  }
  elseif ([string]$observation.kind -ceq 'svg-defaults') {
    Assert-ContractExactFields -Value $observation -Expected @($contract.semanticObservationSchema.svgDefaultsFields) -Description "SVG semantic observation '$observationCase'"
    Assert-ContractCondition -Condition ($observationCase -ceq 'valid.svg-omitted-defaults' -and [string]$observation.scope -ceq 'inline') -Message "SVG semantic observation scope changed."
    foreach ($elementName in @('svg','path')) {
      Assert-ContractExactSet -Actual @($observation.$elementName.PSObject.Properties.Name) -Expected @($contract.standaloneSvg.defaults.$elementName.PSObject.Properties.Name) -Description "SVG semantic observation $elementName defaults"
      foreach ($property in @($contract.standaloneSvg.defaults.$elementName.PSObject.Properties)) {
        Assert-ContractCondition -Condition ([string]$observation.$elementName.($property.Name) -ceq [string]$property.Value) -Message "SVG semantic observation '$elementName.$($property.Name)' changed."
      }
    }
  }
  else {
    throw "Semantic observation '$observationCase' has unknown kind '$($observation.kind)'."
  }
}
Assert-ContractExactSet -Actual @($semanticCases) -Expected (@($expectedCssSemantics.Keys) + @('valid.svg-omitted-defaults')) -Description 'Semantic observation cases'

$expectedUpdateIds = @('snapshot.state.false-true-false-true','snapshot.repeat.0-1-0-1','snapshot.asset.activation-failure')
$expectedUpdateInputs = @{
  'state-transition' = @($false,$true,$false,$true)
  'repeat-transition' = @(0,1,0,1)
  'newly-activated-asset-failure' = @($true)
}
$expectedUpdateTrees = @{
  'state-transition' = @('state-false-1','state-true-2','state-false-3','state-true-4')
  'repeat-transition' = @('repeat-0-1','repeat-1-2','repeat-0-3','repeat-1-4')
  'newly-activated-asset-failure' = @('asset-inactive')
}
$updateScenarioIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($updateScenario in @($corpus.snapshotUpdateScenarios)) {
  $updateId = [string]$updateScenario.id
  $updateKind = [string]$updateScenario.kind
  Assert-ContractExactFields -Value $updateScenario -Expected @($contract.snapshotUpdates.scenarioFields) -Description "Snapshot update scenario '$updateId'"
  Assert-ContractCondition -Condition ($updateScenarioIds.Add($updateId) -and $expectedUpdateIds -ccontains $updateId) -Message "Unknown or duplicate snapshot update scenario '$updateId'."
  Assert-ContractCondition -Condition (@($contract.snapshotUpdates.kinds) -ccontains $updateKind) -Message "Snapshot update scenario '$updateId' has an unknown kind."
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$updateScenario.entryResource) -and @($updateScenario.retainedParsedResources) -ccontains [string]$updateScenario.entryResource) -Message "Snapshot update scenario '$updateId' does not retain its entry resource."
  Assert-ContractExactSet -Actual @($updateScenario.retainedNodeKinds) -Expected @($contract.snapshotUpdates.retainedNodeKinds) -Description "Snapshot update scenario '$updateId' retained nodes"
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$updateScenario.initialParsedRepresentation) -and ![string]::IsNullOrWhiteSpace([string]$updateScenario.initialCommittedTree)) -Message "Snapshot update scenario '$updateId' has no initial immutable representation or tree."
  $expectedInputs = @($expectedUpdateInputs[$updateKind])
  $expectedTrees = @($expectedUpdateTrees[$updateKind])
  $steps = @($updateScenario.steps)
  Assert-ContractCondition -Condition ($steps.Count -eq $expectedInputs.Count -and $steps.Count -eq $expectedTrees.Count) -Message "Snapshot update scenario '$updateId' has the wrong transition count."
  $priorTree = [string]$updateScenario.initialCommittedTree
  for ($stepIndex = 0; $stepIndex -lt $steps.Count; $stepIndex++) {
    $step = $steps[$stepIndex]
    Assert-ContractExactFields -Value $step -Expected @($contract.snapshotUpdates.stepFields) -Description "Snapshot update scenario '$updateId' step $($stepIndex + 1)"
    Assert-ContractCondition -Condition ((Test-ContractInteger -Value $step.sequence) -and [long]$step.sequence -eq $stepIndex + 1) -Message "Snapshot update scenario '$updateId' sequence changed."
    $inputMatches = if ($updateKind -ceq 'repeat-transition') {
      (Test-ContractInteger -Value $step.inputValue) -and [long]$step.inputValue -eq [long]$expectedInputs[$stepIndex]
    }
    else {
      $step.inputValue -is [bool] -and [bool]$step.inputValue -eq [bool]$expectedInputs[$stepIndex]
    }
    Assert-ContractCondition -Condition $inputMatches -Message "Snapshot update scenario '$updateId' input transition changed."
    Assert-ContractExactSet -Actual @($step.previousResourceParseCounts.PSObject.Properties | ForEach-Object { $_.Name }) -Expected @($updateScenario.retainedParsedResources) -Description "Snapshot update scenario '$updateId' previous parse counts"
    foreach ($parseCount in @($step.previousResourceParseCounts.PSObject.Properties)) {
      Assert-ContractCondition -Condition ((Test-ContractInteger -Value $parseCount.Value) -and [long]$parseCount.Value -eq 1) -Message "Snapshot update scenario '$updateId' reparsed '$($parseCount.Name)'."
    }
    Assert-ContractExactSet -Actual @($step.newResourceParseCounts.PSObject.Properties | ForEach-Object { $_.Name }) -Expected @($step.newlyRequiredResources) -Description "Snapshot update scenario '$updateId' new resource parse counts"
    foreach ($newParseCount in @($step.newResourceParseCounts.PSObject.Properties)) {
      Assert-ContractCondition -Condition ((Test-ContractInteger -Value $newParseCount.Value) -and [long]$newParseCount.Value -eq 1 -and @($updateScenario.retainedParsedResources) -cnotcontains $newParseCount.Name -and @($step.pendingCreated) -ccontains "resource:$($newParseCount.Name)") -Message "Snapshot update scenario '$updateId' did not parse and transaction-own a newly required resource exactly once."
    }
    Assert-ContractExactSet -Actual @($step.committedParsedResources) -Expected @($updateScenario.retainedParsedResources) -Description "Snapshot update scenario '$updateId' committed parsed resources"
    Assert-ContractCondition -Condition ([string]$step.currentParsedRepresentation -ceq [string]$updateScenario.initialParsedRepresentation -and [string]$step.currentCommittedTree -ceq [string]$expectedTrees[$stepIndex]) -Message "Snapshot update scenario '$updateId' mutated its immutable parsed representation or selected the wrong tree."
    Assert-ContractCondition -Condition ((Test-ContractInteger -Value $step.terminalPublicationCount) -and [long]$step.terminalPublicationCount -eq 1 -and (Test-ContractInteger -Value $step.fallbackParserInvocations) -and [long]$step.fallbackParserInvocations -eq 0) -Message "Snapshot update scenario '$updateId' published the wrong terminal count or invoked fallback parsing."
    Assert-ContractTerminalResult -Result $step.expected -Description "Snapshot update scenario '$updateId' result" -ContractId $expectedContract -Stages $expectedStages -Codes $expectedCodes -CodeStages $contract.terminalResult.codeStages -LimitById $limitById
    if ($updateKind -ceq 'newly-activated-asset-failure') {
      Assert-ContractExactSet -Actual @($step.pendingDisposed) -Expected @($step.pendingCreated) -Description "Snapshot update scenario '$updateId' pending cleanup"
      Assert-ContractCondition -Condition ([string]$step.currentCommittedTree -ceq [string]$updateScenario.initialCommittedTree -and [string]$step.expected.status -ceq 'rejected' -and [string]$step.expected.stage -ceq 'asset' -and [string]$step.expected.code -ceq 'adapter-failure' -and [string]$step.expected.resource -ceq 'icon.svg' -and $step.expected.committed -eq $false) -Message "Snapshot update scenario '$updateId' did not preserve the prior tree after the asset failure."
    }
    else {
      Assert-ContractCondition -Condition (@($step.newlyRequiredResources).Count -eq 0 -and @($step.pendingCreated).Count -gt 0 -and @($step.pendingDisposed).Count -eq 0 -and [string]$step.currentCommittedTree -cne $priorTree -and [string]$step.expected.status -ceq 'accepted' -and [string]$step.expected.stage -ceq 'lifecycle' -and [string]$step.expected.resource -ceq [string]$updateScenario.entryResource -and $step.expected.committed -eq $true) -Message "Snapshot update scenario '$updateId' did not atomically commit its successful transition."
      $priorTree = [string]$step.currentCommittedTree
    }
  }
}
Assert-ContractExactSet -Actual @($updateScenarioIds) -Expected $expectedUpdateIds -Description 'Snapshot update scenario catalog'

$diskPaths = @(
  Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse | ForEach-Object {
    [IO.Path]::GetRelativePath($corpusRoot, $_.FullName).Replace('\', '/')
  }
)
Assert-ContractExactSet -Actual @($indexedFilePaths) -Expected $diskPaths -Description 'Indexed fixture files'

$expectedScenarioIds = @('transaction.cancellation','transaction.bind-adapter-failure','transaction.lifecycle-failure','transaction.cleanup-preserves-primary','precedence.stage','precedence.resource','precedence.source-offset','precedence.limit-order.forward','precedence.limit-order.reverse')
$scenarioIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$scenarioById = @{}
$stageIndex = @{}
for ($index = 0; $index -lt $expectedStages.Count; $index++) { $stageIndex[$expectedStages[$index]] = $index }
$codeIndex = @{}
for ($index = 0; $index -lt $expectedCodes.Count; $index++) { $codeIndex[$expectedCodes[$index]] = $index }
$limitIndex = @{}
for ($index = 0; $index -lt @($contract.limits).Count; $index++) { $limitIndex[[string]$contract.limits[$index].id] = $index }
foreach ($scenario in @($corpus.scenarios)) {
  $scenarioId = [string]$scenario.id
  Assert-ContractExactFields -Value $scenario -Expected @('id','initialCommittedTree','candidateTree','candidateErrors','cleanupErrors','pendingCreated','observations','expected') -Description "Scenario '$scenarioId'"
  Assert-ContractCondition -Condition $scenarioIds.Add($scenarioId) -Message "Duplicate scenario '$scenarioId'."
  $scenarioById[$scenarioId] = $scenario
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$scenario.initialCommittedTree)) -Message "Scenario '$scenarioId' has no initial tree."
  Assert-ContractCondition -Condition (![string]::IsNullOrWhiteSpace([string]$scenario.candidateTree)) -Message "Scenario '$scenarioId' has no candidate tree."
  Assert-ContractCondition -Condition ([string]$scenario.initialCommittedTree -cne [string]$scenario.candidateTree) -Message "Scenario '$scenarioId' does not model a replacement."
  Assert-ContractExactFields -Value $scenario.observations -Expected @('currentCommittedTree','pendingDisposed','terminalPublicationCount','fallbackParserInvocations') -Description "Scenario '$scenarioId' observations"
  Assert-ContractCondition -Condition ([string]$scenario.observations.currentCommittedTree -ceq [string]$scenario.initialCommittedTree) -Message "Scenario '$scenarioId' did not preserve the existing committed tree."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $scenario.observations.terminalPublicationCount) -and [long]$scenario.observations.terminalPublicationCount -eq 1) -Message "Scenario '$scenarioId' did not publish exactly one terminal result."
  Assert-ContractCondition -Condition ((Test-ContractInteger -Value $scenario.observations.fallbackParserInvocations) -and [long]$scenario.observations.fallbackParserInvocations -eq 0) -Message "Scenario '$scenarioId' invoked a fallback parser."
  Assert-ContractExactSet -Actual @($scenario.observations.pendingDisposed) -Expected @($scenario.pendingCreated) -Description "Scenario '$scenarioId' pending cleanup"
  Assert-ContractCondition -Condition (@($scenario.candidateErrors).Count -gt 0) -Message "Scenario '$scenarioId' has no candidate error."
  foreach ($candidateError in @($scenario.candidateErrors)) {
    Assert-ContractCandidateError -ErrorRecord $candidateError -Description "Scenario '$scenarioId' candidate error" -Stages $expectedStages -Codes $expectedCodes -CodeStages $contract.terminalResult.codeStages -LimitById $limitById
  }
  foreach ($cleanupError in @($scenario.cleanupErrors)) {
    Assert-ContractCandidateError -ErrorRecord $cleanupError -Description "Scenario '$scenarioId' cleanup error" -Stages $expectedStages -Codes $expectedCodes -CodeStages $contract.terminalResult.codeStages -LimitById $limitById
  }
  $candidateErrors = @($scenario.candidateErrors)
  for ($leftIndex = 0; $leftIndex -lt $candidateErrors.Count; $leftIndex++) {
    for ($rightIndex = $leftIndex + 1; $rightIndex -lt $candidateErrors.Count; $rightIndex++) {
      $leftRight = Compare-ContractCandidateError -Left $candidateErrors[$leftIndex] -Right $candidateErrors[$rightIndex] -StageIndex $stageIndex -CodeIndex $codeIndex -LimitIndex $limitIndex
      $rightLeft = Compare-ContractCandidateError -Left $candidateErrors[$rightIndex] -Right $candidateErrors[$leftIndex] -StageIndex $stageIndex -CodeIndex $codeIndex -LimitIndex $limitIndex
      Assert-ContractCondition -Condition ([Math]::Sign($leftRight) -eq -[Math]::Sign($rightLeft)) -Message "Scenario '$scenarioId' comparison is not reversible."
      if ($leftRight -eq 0) {
        foreach ($terminalField in @('stage','code','resource','offset','limitId')) {
          Assert-ContractCondition -Condition ([string]$candidateErrors[$leftIndex].$terminalField -ceq [string]$candidateErrors[$rightIndex].$terminalField) -Message "Scenario '$scenarioId' comparison tied nonidentical terminal fields."
        }
      }
    }
  }
  $selectedError = @($scenario.candidateErrors)[0]
  if (@($scenario.candidateErrors).Count -gt 1) {
    foreach ($candidateError in @($scenario.candidateErrors)[1..(@($scenario.candidateErrors).Count - 1)]) {
      if ((Compare-ContractCandidateError -Left $candidateError -Right $selectedError -StageIndex $stageIndex -CodeIndex $codeIndex -LimitIndex $limitIndex) -lt 0) { $selectedError = $candidateError }
    }
  }
  Assert-ContractTerminalResult -Result $scenario.expected -Description "Scenario '$scenarioId' result" -ContractId $expectedContract -Stages $expectedStages -Codes $expectedCodes -CodeStages $contract.terminalResult.codeStages -LimitById $limitById
  $expectedStatus = if ([string]$selectedError.code -ceq 'cancelled') { 'cancelled' } else { 'rejected' }
  Assert-ContractCondition -Condition ([string]$scenario.expected.status -ceq $expectedStatus) -Message "Scenario '$scenarioId' selected the wrong status."
  foreach ($field in @('stage','code','resource','limitId')) {
    Assert-ContractCondition -Condition ([string]$scenario.expected.$field -ceq [string]$selectedError.$field) -Message "Scenario '$scenarioId' selected the wrong $field."
  }
  Assert-ContractCondition -Condition (($null -eq $scenario.expected.offset -and $null -eq $selectedError.offset) -or ([long]$scenario.expected.offset -eq [long]$selectedError.offset)) -Message "Scenario '$scenarioId' selected the wrong offset."
}
Assert-ContractExactSet -Actual @($scenarioIds) -Expected $expectedScenarioIds -Description 'Stateful scenario catalog'
$forwardLimitScenario = $scenarioById['precedence.limit-order.forward']
$reverseLimitScenario = $scenarioById['precedence.limit-order.reverse']
Assert-ContractCondition -Condition (@($forwardLimitScenario.candidateErrors).Count -eq 2 -and @($reverseLimitScenario.candidateErrors).Count -eq 2) -Message 'Limit-order permutation scenarios have the wrong candidate count.'
Assert-ContractCondition -Condition ((@($forwardLimitScenario.candidateErrors)[0] | ConvertTo-Json -Compress) -ceq (@($reverseLimitScenario.candidateErrors)[1] | ConvertTo-Json -Compress) -and (@($forwardLimitScenario.candidateErrors)[1] | ConvertTo-Json -Compress) -ceq (@($reverseLimitScenario.candidateErrors)[0] | ConvertTo-Json -Compress)) -Message 'Limit-order scenarios are not exact reversals.'
Assert-ContractCondition -Condition (($forwardLimitScenario.expected | ConvertTo-Json -Compress) -ceq ($reverseLimitScenario.expected | ConvertTo-Json -Compress)) -Message 'Limit-order reversal changed the selected terminal result.'

Write-Output "HTML Engine contract integrity passed: $($caseIds.Count) deterministic cases, $($limitById.Count) constructible at/over pairs, $($scenarioIds.Count) failure scenarios, $($updateScenarioIds.Count) snapshot-update scenarios, frozen manifest/fixture digests, Canvas parser-route observations, typed out-of-band bindings, semantic expectations, and modeled raw/absent resources. No HTML/CSS/SVG parser or runtime engine was executed."
