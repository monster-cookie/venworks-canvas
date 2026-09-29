package
{
   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   public final class CanvasHtmlData
   {
      // Last value the HTML data copier or renderer was touching. The ready-callback
      // diagnostic prints this because Scaleform's ReferenceError #1069 text omits the property.
      public static var access:String = "";

      public static function snapshot(param1:Object) : Object
      {
         access = "data";
         if(param1 == null)
         {
            return {};
         }
         if(isDataArray(param1,"data") || typeof param1 != "object")
         {
            throw new Error("Canvas HTML data root must be an object");
         }
         var result:Object = {};
         var seen:Dictionary = new Dictionary(false);
         seen[param1] = true;
         var frames:Array = [{"source":param1,"target":result,"depth":1,"path":"data"}];
         var nodeCount:int = 1;
         var entryCount:int = 0;
         var stringCodeUnits:int = 0;
         while(frames.length > 0)
         {
            var frame:Object = frames.pop();
            if(int(frame.depth) > CanvasHtmlLimits.MAX_DATA_DEPTH)
            {
               throw new Error("Canvas HTML data exceeds maximum depth");
            }
            var source:Object = frame.source;
            var target:Object = frame.target;
            var path:String = frame.path == null ? "data" : String(frame.path);
            access = path;
            if(isDataArray(source,path))
            {
               var sourceLength:int = int(readProperty(source,"length",path + "#length"));
               if(sourceLength > CanvasHtmlLimits.MAX_REPEAT_ITEMS)
               {
                  throw new Error("Canvas HTML data array exceeds item limit");
               }
               for(var arrayIndex:int = 0; arrayIndex < sourceLength; arrayIndex++)
               {
                  entryCount++;
                  if(entryCount > CanvasHtmlLimits.MAX_DATA_ENTRIES)
                  {
                     throw new Error("Canvas HTML data exceeds entry limit");
                  }
                  var indexPath:String = path + "[" + arrayIndex + "]";
                  var arrayValue:* = readProperty(source,String(arrayIndex),indexPath);
                  if(isScalar(arrayValue))
                  {
                     target[arrayIndex] = copyScalar(arrayValue);
                     if(typeof arrayValue == "string")
                     {
                        stringCodeUnits += String(arrayValue).length;
                     }
                  }
                  else
                  {
                     target[arrayIndex] = makeChild(arrayValue,seen,frames,int(frame.depth) + 1,indexPath);
                     nodeCount++;
                  }
                  if(nodeCount > CanvasHtmlLimits.MAX_DATA_NODES)
                  {
                     throw new Error("Canvas HTML data exceeds node limit");
                  }
                  if(stringCodeUnits > CanvasHtmlLimits.MAX_DATA_STRING_CODE_UNITS)
                  {
                     throw new Error("Canvas HTML data exceeds aggregate string limit");
                  }
               }
            }
            else
            {
               var propertyCount:int = 0;
               var key:String = null;
               var keys:Array = enumerateKeys(source,path);
               for(var keyIndex:int = 0; keyIndex < keys.length; keyIndex++)
               {
                  key = String(keys[keyIndex]);
                  var propertyPath:String = path + "." + key;
                  if(!ownsProperty(source,key,propertyPath))
                  {
                     continue;
                  }
                  if(!isDataIdentifier(key))
                  {
                     throw new Error("Canvas HTML data contains an invalid property: " + key);
                  }
                  propertyCount++;
                  entryCount++;
                  if(propertyCount > CanvasHtmlLimits.MAX_DATA_PROPERTIES)
                  {
                     throw new Error("Canvas HTML data object exceeds property limit");
                  }
                  if(entryCount > CanvasHtmlLimits.MAX_DATA_ENTRIES)
                  {
                     throw new Error("Canvas HTML data exceeds entry limit");
                  }
                  stringCodeUnits += key.length;
                  var propertyValue:* = readProperty(source,key,propertyPath);
                  if(isScalar(propertyValue))
                  {
                     target[key] = copyScalar(propertyValue);
                     if(typeof propertyValue == "string")
                     {
                        stringCodeUnits += String(propertyValue).length;
                     }
                  }
                  else
                  {
                     target[key] = makeChild(propertyValue,seen,frames,int(frame.depth) + 1,propertyPath);
                     nodeCount++;
                  }
                  if(nodeCount > CanvasHtmlLimits.MAX_DATA_NODES)
                  {
                     throw new Error("Canvas HTML data exceeds node limit");
                  }
                  if(stringCodeUnits > CanvasHtmlLimits.MAX_DATA_STRING_CODE_UNITS)
                  {
                     throw new Error("Canvas HTML data exceeds aggregate string limit");
                  }
               }
            }
         }
         return result;
      }

      public static function resolve(param1:Object, param2:String) : Object
      {
         var scope:Object = param1;
         var depth:int = 0;
         while(scope != null && depth <= CanvasHtmlLimits.MAX_DATA_DEPTH)
         {
            var values:Object = scope.values;
            if(values != null && values.hasOwnProperty(param2))
            {
               return {"found":true,"value":values[param2]};
            }
            scope = scope.parent;
            depth++;
         }
         return {"found":false,"value":null};
      }

      public static function toText(param1:*) : String
      {
         if(param1 == null)
         {
            return "";
         }
         if(typeof param1 == "string" || typeof param1 == "boolean" || typeof param1 == "number")
         {
            var value:String = String(param1);
            if(value.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
            {
               throw new Error("Canvas HTML bound text exceeds string limit");
            }
            return value;
         }
         throw new Error("Canvas HTML bound text must be scalar");
      }

      public static function formatText(param1:String, param2:String) : String
      {
         if(param1 == null || param1.length == 0 || param1.length > CanvasHtmlLimits.MAX_FORMAT_CODE_UNITS)
         {
            throw new Error("Canvas HTML data format is invalid");
         }
         var marker:String = "{value}";
         var markerIndex:int = param1.indexOf(marker);
         if(markerIndex < 0 || markerIndex != param1.lastIndexOf(marker))
         {
            throw new Error("Canvas HTML data format is invalid");
         }
         var before:String = param1.substring(0,markerIndex);
         var after:String = param1.substring(markerIndex + marker.length);
         if(before.indexOf("{") >= 0 || before.indexOf("}") >= 0 || after.indexOf("{") >= 0 || after.indexOf("}") >= 0)
         {
            throw new Error("Canvas HTML data format is invalid");
         }
         var result:String = before + (param2 == null ? "" : param2) + after;
         if(result.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
         {
            throw new Error("Canvas HTML formatted text exceeds string limit");
         }
         return result;
      }

      public static function isDataIdentifier(param1:String) : Boolean
      {
         return param1 != null && param1.length > 0 && param1.length <= CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH && /^[a-z][a-z0-9-]*(?:\.[a-z][a-z0-9-]*)*$/.test(param1);
      }

      public static function validateTemplate(param1:String) : Boolean
      {
         parseTemplate(param1);
         return true;
      }

      public static function formatTemplate(param1:String, param2:Object) : String
      {
         var variables:Array = parseTemplate(param1);
         var result:String = param1;
         var variable:Object = null;
         var resolved:Object = null;
         var replacement:String = null;
         for each(variable in variables)
         {
            resolved = resolve(param2,String(variable.source));
            replacement = resolved.found ? formatTemplateValue(resolved.value,String(variable.format)) : "";
            result = result.split(String(variable.token)).join(replacement);
            if(result.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
            {
               throw new Error("Canvas HTML formatted template exceeds string limit");
            }
         }
         return result;
      }

      private static function makeChild(param1:*, param2:Dictionary, param3:Array, param4:int, param5:String) : Object
      {
         if(param1 == null || typeof param1 != "object")
         {
            throw new Error("Canvas HTML data contains an unsupported value");
         }
         if(param2[param1] === true)
         {
            throw new Error("Canvas HTML data cannot contain cycles or aliases");
         }
         param2[param1] = true;
         var child:Object = isDataArray(param1,param5) ? [] : {};
         param3.push({"source":param1,"target":child,"depth":param4,"path":param5});
         return child;
      }

      // A consumer movie can create arrays in another application domain, where `is Array` is false.
      // getQualifiedClassName still reports those as Array. A length property alone is an object field.
      private static function isDataArray(param1:*, param2:String) : Boolean
      {
         if(param1 is Array)
         {
            return true;
         }
         if(param1 == null || typeof param1 != "object")
         {
            return false;
         }
         try
         {
            if(getQualifiedClassName(param1) == "Array")
            {
               return true;
            }
         }
         catch(classError:*)
         {
         }
         access = param2 + "#length";
         var lengthValue:* = undefined;
         try
         {
            lengthValue = param1["length"];
         }
         catch(lengthError:*)
         {
            if(isReportedAccessFailure(lengthError))
            {
               throw describeAccess(param2 + "#length",lengthError);
            }
            return false;
         }
         if(typeof lengthValue != "number" || !isFinite(Number(lengthValue)) || Number(lengthValue) < 0 || int(lengthValue) != Number(lengthValue))
         {
            return false;
         }
         var length:int = int(lengthValue);
         access = param2 + "#keys";
         var key:String = null;
         var sawIndex:Boolean = false;
         try
         {
            for(key in param1)
            {
               if(key == "length")
               {
                  continue;
               }
               if(key.length == 0 || key.length > 10 || (key.charAt(0) == "0" && key.length > 1))
               {
                  return false;
               }
               var index:Number = Number(key);
               if(!isFinite(index) || int(index) != index || index < 0 || index >= length || String(int(index)) != key)
               {
                  return false;
               }
               sawIndex = true;
            }
         }
         catch(enumerateError:*)
         {
            if(isReportedAccessFailure(enumerateError))
            {
               throw describeAccess(param2 + "#keys",enumerateError);
            }
            return false;
         }
         return sawIndex;
      }

      public static function describeAccess(path:String, error:*) : Error
      {
         var text:String = "error";
         try
         {
            text = String(error);
         }
         catch(ignored:*)
         {
            text = "unprintable";
         }
         if((text.indexOf("Canvas HTML") == 0 || text.indexOf("1069 ") == 0 || text.indexOf("PUBLISH ") == 0) && error is Error)
         {
            return error as Error;
         }
         var where:String = path == null || path.length == 0 ? "?" : path;
         if(where.length > 72)
         {
            where = where.substr(0,69) + "...";
         }
         var code:String = "ERR";
         var marker:int = text.indexOf("#");
         if(marker >= 0)
         {
            var digits:String = "";
            var cursor:int = marker + 1;
            while(cursor < text.length && digits.length < 6)
            {
               var character:String = text.charAt(cursor);
               if(character < "0" || character > "9")
               {
                  break;
               }
               digits += character;
               cursor++;
            }
            if(digits.length > 0)
            {
               code = digits;
            }
         }
         access = where;
         return new Error(code + " " + where);
      }

      private static function readProperty(source:Object, key:String, path:String) : *
      {
         access = path;
         try
         {
            return source[key];
         }
         catch(error:*)
         {
            throw describeAccess(path,error);
         }
         return undefined;
      }

      private static function ownsProperty(source:Object, key:String, path:String) : Boolean
      {
         access = path + "#own";
         try
         {
            return source.hasOwnProperty(key);
         }
         catch(error:*)
         {
            throw describeAccess(path + "#own",error);
         }
         return false;
      }

      private static function enumerateKeys(source:Object, path:String) : Array
      {
         access = path + "#keys";
         var keys:Array = [];
         var key:String = null;
         try
         {
            for(key in source)
            {
               keys.push(key);
            }
         }
         catch(error:*)
         {
            throw describeAccess(path + "#keys",error);
         }
         return keys;
      }

      private static function isReportedAccessFailure(error:*) : Boolean
      {
         if(error is ReferenceError)
         {
            return true;
         }
         var text:String = "";
         try
         {
            text = String(error);
         }
         catch(ignored:*)
         {
            return false;
         }
         return text.indexOf("#1069") >= 0;
      }

      private static function isScalar(param1:*) : Boolean
      {
         return param1 == null || typeof param1 == "string" || typeof param1 == "boolean" || typeof param1 == "number";
      }

      private static function copyScalar(param1:*) : *
      {
         if(typeof param1 == "number" && !isFinite(Number(param1)))
         {
            throw new Error("Canvas HTML data contains a non-finite number");
         }
         if(typeof param1 == "string" && String(param1).length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
         {
            throw new Error("Canvas HTML data string exceeds limit");
         }
         return param1;
      }

      private static function parseTemplate(param1:String) : Array
      {
         if(param1 == null || param1.length == 0 || param1.length > CanvasHtmlLimits.MAX_FORMAT_CODE_UNITS)
         {
            throw new Error("Canvas HTML data template is invalid");
         }
         var variables:Array = [];
         var cursor:int = 0;
         var openIndex:int = 0;
         var closeIndex:int = 0;
         var body:String = null;
         var separatorIndex:int = 0;
         var source:String = null;
         var format:String = null;
         while(cursor < param1.length)
         {
            if(param1.charAt(cursor) == "}")
            {
               throw new Error("Canvas HTML data template is malformed");
            }
            if(param1.charAt(cursor) != "{")
            {
               cursor++;
               continue;
            }
            openIndex = cursor;
            closeIndex = param1.indexOf("}",openIndex + 1);
            if(closeIndex < 0 || param1.indexOf("{",openIndex + 1) >= 0 && param1.indexOf("{",openIndex + 1) < closeIndex)
            {
               throw new Error("Canvas HTML data template is malformed");
            }
            body = param1.substring(openIndex + 1,closeIndex);
            separatorIndex = body.indexOf(":");
            source = separatorIndex < 0 ? body : body.substring(0,separatorIndex);
            format = separatorIndex < 0 ? "raw" : body.substring(separatorIndex + 1).toLowerCase();
            if(!isDataIdentifier(source) || separatorIndex >= 0 && body.indexOf(":",separatorIndex + 1) >= 0 || !isTemplateFormat(format))
            {
               throw new Error("Canvas HTML data template variable is invalid");
            }
            variables.push({"source":source,"format":format,"token":param1.substring(openIndex,closeIndex + 1)});
            if(variables.length > CanvasHtmlLimits.MAX_TEMPLATE_VARIABLES)
            {
               throw new Error("Canvas HTML data template exceeds variable limit");
            }
            cursor = closeIndex + 1;
         }
         if(variables.length == 0)
         {
            throw new Error("Canvas HTML data template requires a variable");
         }
         return variables;
      }

      private static function isTemplateFormat(param1:String) : Boolean
      {
         return param1 == "raw" || param1 == "integer" || param1 == "percent" || param1 == "temperature" || param1 == "gravity" || param1 == "time24" || param1 == "boolean";
      }

      private static function formatTemplateValue(param1:*, param2:String) : String
      {
         if(param2 == "raw")
         {
            return toText(param1);
         }
         if(param2 == "boolean")
         {
            if(typeof param1 != "boolean")
            {
               throw new Error("Canvas HTML boolean template value is invalid");
            }
            return Boolean(param1) ? "TRUE" : "FALSE";
         }
         if(typeof param1 != "number" || !isFinite(Number(param1)))
         {
            throw new Error("Canvas HTML numeric template value is invalid");
         }
         var numeric:Number = Number(param1);
         if(param2 == "integer")
         {
            return Math.round(numeric).toString();
         }
         if(param2 == "percent")
         {
            return Math.round(numeric).toString() + "%";
         }
         if(param2 == "temperature")
         {
            return Math.round(numeric).toString() + "°";
         }
         if(param2 == "gravity")
         {
            return numeric.toFixed(2) + "g";
         }
         numeric = numeric - Math.floor(numeric);
         if(numeric < 0)
         {
            numeric += 1;
         }
         var totalMinutes:int = Math.floor(numeric * 1440 + 0.5) % 1440;
         var hours:int = int(totalMinutes / 60);
         var minutes:int = totalMinutes % 60;
         return (hours < 10 ? "0" : "") + hours.toString() + ":" + (minutes < 10 ? "0" : "") + minutes.toString();
      }
   }
}
