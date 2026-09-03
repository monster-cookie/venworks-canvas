<#
.SYNOPSIS
Refuses unsafe YAML-to-ESM assembly. Canvas uses verified binary inputs and Spriggit serialization only.
#>
[CmdletBinding()]
param()
throw 'Spriggit assembly is disabled for Canvas. Use verified Mutagen/CK binary inputs, then Tools/SpriggitDumpDatabaseToYaml.ps1 -PluginsDirectory <profile-directory> -ProbeProfile <profile> for review-only YAML.'
