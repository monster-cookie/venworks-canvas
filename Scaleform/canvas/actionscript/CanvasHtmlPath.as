package
{
   public final class CanvasHtmlPath
   {
      public static function isValidNamespace(param1:String) : Boolean
      {
         var code:int = 0;
         if(param1 == null || param1.length < 3 || param1.length > 64 || param1.indexOf("..") >= 0)
         {
            return false;
         }
         for(var index:int = 0; index < param1.length; index++)
         {
            code = param1.charCodeAt(index);
            if(!(code >= 97 && code <= 122 || code >= 48 && code <= 57 || code == 46 || code == 45))
            {
               return false;
            }
         }
         code = param1.charCodeAt(0);
         if(!(code >= 97 && code <= 122 || code >= 48 && code <= 57))
         {
            return false;
         }
         code = param1.charCodeAt(param1.length - 1);
         return code >= 97 && code <= 122 || code >= 48 && code <= 57;
      }

      public static function isValid(param1:String, param2:String = null) : Boolean
      {
         var segment:String = null;
         var code:int = 0;
         var index:int = 0;
         if(param1 == null || param1.length == 0 || param1.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
         {
            return false;
         }
         if(param1.indexOf("\\") >= 0 || param1.indexOf(":") >= 0 || param1.indexOf("?") >= 0 || param1.indexOf("#") >= 0 || param1.indexOf("%") >= 0 || param1.charAt(0) == "/")
         {
            return false;
         }
         var segments:Array = param1.split("/");
         for each(segment in segments)
         {
            if(segment.length == 0 || segment == "." || segment == "..")
            {
               return false;
            }
            for(index = 0; index < segment.length; index++)
            {
               code = segment.charCodeAt(index);
               if(!isPathCharacter(code))
               {
                  return false;
               }
            }
            code = segment.charCodeAt(0);
            if(!(code >= 97 && code <= 122 || code >= 48 && code <= 57))
            {
               return false;
            }
         }
         var extension:String = getExtension(param1);
         if(extension != ".html" && extension != ".css" && extension != ".svg" && extension != ".png")
         {
            return false;
         }
         return param2 == null || extension == param2;
      }

      public static function resolve(param1:String, param2:String) : String
      {
         if(!isValid(param2))
         {
            return null;
         }
         var separator:int = param1.lastIndexOf("/");
         if(separator < 0)
         {
            return param2;
         }
         var resolved:String = param1.substring(0,separator + 1) + param2;
         return isValid(resolved) ? resolved : null;
      }

      public static function getExtension(param1:String) : String
      {
         var dot:int = param1.lastIndexOf(".");
         return dot < 0 ? "" : param1.substring(dot);
      }

      private static function isPathCharacter(param1:int) : Boolean
      {
         return param1 >= 97 && param1 <= 122 || param1 >= 48 && param1 <= 57 || param1 == 46 || param1 == 95 || param1 == 45;
      }
   }
}
