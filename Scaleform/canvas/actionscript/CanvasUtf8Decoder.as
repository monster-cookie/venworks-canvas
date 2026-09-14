package
{
   import flash.utils.ByteArray;

   public final class CanvasUtf8Decoder
   {
      public static function decode(param1:ByteArray) : CanvasUtf8Result
      {
         var b0:int = 0;
         var b1:int = 0;
         var b2:int = 0;
         var b3:int = 0;
         var codePoint:int = 0;
         var high:int = 0;
         var low:int = 0;
         var output:Array = [];
         var index:int = 0;
         var length:int = param1.length;
         if(length >= 3 && int(param1[0]) == 239 && int(param1[1]) == 187 && int(param1[2]) == 191)
         {
            return new CanvasUtf8Result(false,null,0);
         }
         while(index < length)
         {
            b0 = int(param1[index]);
            if(b0 <= 127)
            {
               output.push(String.fromCharCode(b0));
               index++;
               continue;
            }
            if(b0 >= 194 && b0 <= 223)
            {
               if(index + 1 >= length)
               {
                  return new CanvasUtf8Result(false,null,index);
               }
               b1 = int(param1[index + 1]);
               if(!isContinuation(b1))
               {
                  return new CanvasUtf8Result(false,null,index + 1);
               }
               output.push(String.fromCharCode(((b0 & 31) << 6) | (b1 & 63)));
               index += 2;
               continue;
            }
            if(b0 >= 224 && b0 <= 239)
            {
               if(index + 2 >= length)
               {
                  return new CanvasUtf8Result(false,null,index);
               }
               b1 = int(param1[index + 1]);
               b2 = int(param1[index + 2]);
               if(!isContinuation(b1))
               {
                  return new CanvasUtf8Result(false,null,index + 1);
               }
               if(!isContinuation(b2))
               {
                  return new CanvasUtf8Result(false,null,index + 2);
               }
               if(b0 == 224 && b1 < 160 || b0 == 237 && b1 > 159)
               {
                  return new CanvasUtf8Result(false,null,index);
               }
               output.push(String.fromCharCode(((b0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63)));
               index += 3;
               continue;
            }
            if(b0 >= 240 && b0 <= 244)
            {
               if(index + 3 >= length)
               {
                  return new CanvasUtf8Result(false,null,index);
               }
               b1 = int(param1[index + 1]);
               b2 = int(param1[index + 2]);
               b3 = int(param1[index + 3]);
               if(!isContinuation(b1))
               {
                  return new CanvasUtf8Result(false,null,index + 1);
               }
               if(!isContinuation(b2))
               {
                  return new CanvasUtf8Result(false,null,index + 2);
               }
               if(!isContinuation(b3))
               {
                  return new CanvasUtf8Result(false,null,index + 3);
               }
               if(b0 == 240 && b1 < 144 || b0 == 244 && b1 > 143)
               {
                  return new CanvasUtf8Result(false,null,index);
               }
               codePoint = ((b0 & 7) << 18) | ((b1 & 63) << 12) | ((b2 & 63) << 6) | (b3 & 63);
               codePoint -= 65536;
               high = 55296 + (codePoint >> 10);
               low = 56320 + (codePoint & 1023);
               output.push(String.fromCharCode(high,low));
               index += 4;
               continue;
            }
            return new CanvasUtf8Result(false,null,index);
         }
         return new CanvasUtf8Result(true,output.join(""),-1);
      }

      public static function byteOffset(param1:String, param2:int) : int
      {
         var code:int = 0;
         var next:int = 0;
         var bytes:int = 0;
         var limit:int = Math.min(Math.max(param2,0),param1.length);
         var index:int = 0;
         while(index < limit)
         {
            code = param1.charCodeAt(index);
            if(code <= 127)
            {
               bytes++;
            }
            else if(code <= 2047)
            {
               bytes += 2;
            }
            else if(code >= 55296 && code <= 56319 && index + 1 < limit)
            {
               next = param1.charCodeAt(index + 1);
               if(next >= 56320 && next <= 57343)
               {
                  bytes += 4;
                  index++;
               }
               else
               {
                  bytes += 3;
               }
            }
            else
            {
               bytes += 3;
            }
            index++;
         }
         return bytes;
      }

      private static function isContinuation(param1:int) : Boolean
      {
         return param1 >= 128 && param1 <= 191;
      }
   }
}
