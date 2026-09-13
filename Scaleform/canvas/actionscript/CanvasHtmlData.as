package
{
   import flash.utils.Dictionary;

   public final class CanvasHtmlData
   {
      public static function snapshot(param1:Object) : Object
      {
         if(param1 == null)
         {
            return {};
         }
         if(param1 is Array || typeof param1 != "object")
         {
            throw new Error("Canvas HTML data root must be an object");
         }
         var result:Object = {};
         var seen:Dictionary = new Dictionary(false);
         seen[param1] = true;
         var frames:Array = [{"source":param1,"target":result,"depth":1}];
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
            if(source is Array)
            {
               var sourceArray:Array = source as Array;
               if(sourceArray.length > CanvasHtmlLimits.MAX_REPEAT_ITEMS)
               {
                  throw new Error("Canvas HTML data array exceeds item limit");
               }
               for(var arrayIndex:int = 0; arrayIndex < sourceArray.length; arrayIndex++)
               {
                  entryCount++;
                  if(entryCount > CanvasHtmlLimits.MAX_DATA_ENTRIES)
                  {
                     throw new Error("Canvas HTML data exceeds entry limit");
                  }
                  var arrayValue:* = sourceArray[arrayIndex];
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
                     target[arrayIndex] = makeChild(arrayValue,seen,frames,int(frame.depth) + 1);
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
               for(key in source)
               {
                  if(!source.hasOwnProperty(key) || !isIdentifier(key))
                  {
                     throw new Error("Canvas HTML data contains an invalid property");
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
                  var propertyValue:* = source[key];
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
                     target[key] = makeChild(propertyValue,seen,frames,int(frame.depth) + 1);
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

      private static function makeChild(param1:*, param2:Dictionary, param3:Array, param4:int) : Object
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
         var child:Object = param1 is Array ? [] : {};
         param3.push({"source":param1,"target":child,"depth":param4});
         return child;
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

      private static function isIdentifier(param1:String) : Boolean
      {
         return param1 != null && param1.length > 0 && param1.length <= CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH && /^[a-z][a-z0-9-]*$/.test(param1);
      }
   }
}
