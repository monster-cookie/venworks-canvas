package
{
   public final class CanvasCssImportScanner
   {
      public function scan(param1:String, param2:String) : CanvasCssImportResult
      {
         var original:String = param1 == null ? "" : param1;
         var source:String = this.stripComments(original,param2);
         if(source == null)
         {
            return new CanvasCssImportResult(false,null,0,[],this.failure);
         }
         var imports:Array = [];
         var index:int = this.skipWhitespace(source,0);
         while(index < source.length && source.substr(index,7) == "@import")
         {
            var importOffset:int = index;
            index += 7;
            if(index >= source.length || !this.isWhitespace(source.charCodeAt(index)))
            {
               return this.reject("malformed-import",original,param2,importOffset);
            }
            index = this.skipWhitespace(source,index);
            if(index >= source.length || source.charAt(index) != "\"")
            {
               return this.reject("unsupported-import",original,param2,index);
            }
            var pathStart:int = ++index;
            while(index < source.length && source.charAt(index) != "\"" && source.charCodeAt(index) != 10 && source.charCodeAt(index) != 13 && source.charAt(index) != "\\")
            {
               index++;
            }
            if(index >= source.length || source.charAt(index) != "\"")
            {
               return this.reject("malformed-import",original,param2,pathStart);
            }
            var path:String = source.substring(pathStart,index);
            if(!CanvasHtmlPath.isValid(path,".css"))
            {
               return this.reject("invalid-path",original,param2,pathStart,"asset");
            }
            index = this.skipWhitespace(source,index + 1);
            if(index >= source.length || source.charAt(index) != ";")
            {
               return this.reject("malformed-import",original,param2,index);
            }
            imports.push({"path":path,"offset":pathStart,"byteOffset":CanvasUtf8Decoder.byteOffset(original,pathStart)});
            if(imports.length > CanvasHtmlLimits.MAX_CSS_IMPORTS)
            {
               return this.reject("limit-exceeded",original,param2,importOffset,"style","css-import-count");
            }
            index = this.skipWhitespace(source,index + 1);
         }
         if(source.indexOf("@",index) >= 0)
         {
            return this.reject("unsupported-at-rule",original,param2,source.indexOf("@",index));
         }
         return new CanvasCssImportResult(true,source,index,imports,null);
      }

      private var failure:CanvasHtmlDiagnostic;

      private function stripComments(param1:String, param2:String) : String
      {
         this.failure = null;
         var output:String = "";
         var index:int = 0;
         while(index < param1.length)
         {
            if(index + 1 < param1.length && param1.charAt(index) == "/" && param1.charAt(index + 1) == "*")
            {
               var end:int = param1.indexOf("*/",index + 2);
               if(end < 0)
               {
                  this.failure = new CanvasHtmlDiagnostic("style","malformed-syntax",param2,CanvasUtf8Decoder.byteOffset(param1,index));
                  return null;
               }
               while(index < end + 2)
               {
                  output += " ";
                  index++;
               }
            }
            else
            {
               output += param1.charAt(index);
               index++;
            }
         }
         return output;
      }

      private function skipWhitespace(param1:String, param2:int) : int
      {
         while(param2 < param1.length && this.isWhitespace(param1.charCodeAt(param2)))
         {
            param2++;
         }
         return param2;
      }

      private function isWhitespace(param1:int) : Boolean
      {
         return param1 == 9 || param1 == 10 || param1 == 12 || param1 == 13 || param1 == 32;
      }

      private function reject(param1:String, param2:String, param3:String, param4:int, param5:String = "style", param6:String = null) : CanvasCssImportResult
      {
         return new CanvasCssImportResult(false,null,0,[],new CanvasHtmlDiagnostic(param5,param1,param3,CanvasUtf8Decoder.byteOffset(param2,param4),param6));
      }
   }
}
