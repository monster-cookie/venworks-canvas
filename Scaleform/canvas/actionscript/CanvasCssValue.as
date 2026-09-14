package
{
   public final class CanvasCssValue
   {
      public static function trim(param1:String) : String
      {
         return param1 == null ? "" : param1.replace(/^\s+|\s+$/g,"");
      }

      public static function parseLength(param1:String, param2:Boolean, param3:Boolean, param4:Boolean) : Object
      {
         var value:String = trim(param1);
         if(param2 && value == "auto")
         {
            return {"unit":"auto","value":0};
         }
         var unit:String = "";
         if(value.length > 2 && value.substr(value.length - 2) == "px")
         {
            unit = "px";
            value = value.substr(0,value.length - 2);
         }
         else if(param3 && value.length > 1 && value.charAt(value.length - 1) == "%")
         {
            unit = "%";
            value = value.substr(0,value.length - 1);
         }
         else if(value == "0")
         {
            unit = "px";
         }
         else
         {
            return null;
         }
         if(!/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(value))
         {
            return null;
         }
         var number:Number = Number(value);
         if(!isFinite(number) || !param4 && number < 0 || Math.abs(number) > 8192 || unit == "%" && Math.abs(number) > 100)
         {
            return null;
         }
         return {"unit":unit,"value":number};
      }

      public static function resolveLength(param1:String, param2:Number, param3:Number) : Number
      {
         var parsed:Object = parseLength(param1,true,true,true);
         if(parsed == null || parsed.unit == "auto")
         {
            return param3;
         }
         if(parsed.unit == "%")
         {
            return param2 * Number(parsed.value) / 100;
         }
         return Number(parsed.value);
      }

      public static function parseColor(param1:String) : Object
      {
         var value:String = trim(param1).toLowerCase();
         if(value == "transparent")
         {
            return {"color":0,"alpha":0};
         }
         if(value.length != 7 && value.length != 9 || value.charAt(0) != "#" || !/^[0-9a-f]+$/.test(value.substr(1)))
         {
            return null;
         }
         var color:uint = uint(parseInt(value.substr(1,6),16));
         var alpha:Number = value.length == 9 ? Number(parseInt(value.substr(7,2),16)) / 255 : 1;
         return {"color":color,"alpha":alpha};
      }

      public static function isFontFamily(param1:String) : Boolean
      {
         return param1 != null && param1.length > 0 && param1.length <= 64 && /^[A-Za-z_$][A-Za-z0-9_$ .-]*$/.test(param1);
      }
   }
}
