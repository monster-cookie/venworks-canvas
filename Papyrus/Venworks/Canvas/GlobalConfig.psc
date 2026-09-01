ScriptName Venworks:Canvas:GlobalConfig Extends ScriptObject Hidden

Struct Creation
  String Name = "Venworks-Canvas"
EndStruct

String Function GetCreationName() Global
  Creation mod = new Creation
  Return mod.Name
EndFunction