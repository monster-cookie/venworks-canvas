package
{
   import flash.display.BitmapData;

   // One grayscale cloud, tinted per plate color. The theme color stays on the element.
   public final class CanvasHtmlSmoke
   {
      private static const SIZE:int = 64;

      private static var gray:BitmapData;

      private static var tinted:Object = {};

      public static function tintedBitmap(color:uint, alpha:Number) : BitmapData
      {
         var amount:int = int(Math.max(0,Math.min(1,alpha)) * 255 + 0.5);
         if(amount == 0) return null;
         var key:String = color.toString(16) + ":" + String(amount);
         if(tinted[key] != null) return tinted[key] as BitmapData;
         var source:BitmapData = cloud();
         if(source == null) return null;
         var red:int = (color >> 16) & 255;
         var green:int = (color >> 8) & 255;
         var blue:int = color & 255;
         var pixels:BitmapData = new BitmapData(SIZE,SIZE,true,0);
         var y:int = 0;
         while(y < SIZE)
         {
            var x:int = 0;
            while(x < SIZE)
            {
               var lum:int = source.getPixel(x,y) & 255;
               var shaped:int = 80 + ((lum * 175) >> 8);
               var pixelAlpha:int = (shaped * amount) >> 8;
               pixels.setPixel32(x,y,(pixelAlpha << 24) | (red << 16) | (green << 8) | blue);
               ++x;
            }
            ++y;
         }
         tinted[key] = pixels;
         return pixels;
      }

      private static function cloud() : BitmapData
      {
         if(gray != null) return gray;
         gray = new BitmapData(SIZE,SIZE,false,0x808080);
         try { gray.perlinNoise(22,22,4,9,true,true,7,true); }
         catch(noiseError:*) { gray.noise(9,30,220,7,true); }
         return gray;
      }
   }
}
