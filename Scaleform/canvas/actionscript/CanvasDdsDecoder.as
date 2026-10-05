package
{
   import flash.display.BitmapData;
   import flash.geom.Rectangle;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   // Mip 0 only. Uncompressed A8R8G8B8 and DXT1/DXT5 are returned as pixels. Starfield throws on BitmapData.setPixels, so upload runs later with setPixel32 and then fillRect.
   public final class CanvasDdsDecoder
   {
      private static const MAX_DIMENSION:int = 1024;

      public static function read(bytes:ByteArray) : Object
      {
         if(bytes == null || bytes.length < 128) return null;
         bytes.endian = Endian.LITTLE_ENDIAN;
         bytes.position = 0;
         if(readCode(bytes) != "DDS ") return null;
         if(bytes.readUnsignedInt() != 124) return null;
         var flags:uint = bytes.readUnsignedInt();
         var height:int = bytes.readUnsignedInt();
         var width:int = bytes.readUnsignedInt();
         var pitch:int = bytes.readUnsignedInt();
         bytes.position = 76;
         if(bytes.readUnsignedInt() != 32) return null;
         var formatFlags:uint = bytes.readUnsignedInt();
         var fourCC:String = readCode(bytes);
         var bitCount:int = bytes.readUnsignedInt();
         var redMask:uint = bytes.readUnsignedInt();
         var greenMask:uint = bytes.readUnsignedInt();
         var blueMask:uint = bytes.readUnsignedInt();
         var alphaMask:uint = bytes.readUnsignedInt();
         if(width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) return null;
         if(fourCC == "DXT1" || fourCC == "DXT5") return compressed(bytes,width,height,fourCC);
         if((formatFlags & 0x40) != 0 && bitCount == 32 && redMask == 0x00FF0000 && greenMask == 0x0000FF00 && blueMask == 0x000000FF && (alphaMask == 0xFF000000 || alphaMask == 0))
            return uncompressed(bytes,width,height,pitch,flags,alphaMask == 0);
         return null;
      }

      private static function uncompressed(bytes:ByteArray, width:int, height:int, pitch:int, flags:uint, opaque:Boolean) : Object
      {
         var rowBytes:int = width * 4;
         var stride:int = (flags & 0x8) != 0 && (flags & 0x80000) == 0 && pitch > rowBytes ? pitch : rowBytes;
         if(stride < rowBytes || bytes.length < 128 + stride * (height - 1) + rowBytes) return null;
         var pixels:ByteArray = new ByteArray();
         pixels.endian = Endian.BIG_ENDIAN;
         pixels.length = width * height * 4;
         var y:int = 0;
         while(y < height)
         {
            bytes.position = 128 + y * stride;
            var x:int = 0;
            while(x < width)
            {
               var blue:int = bytes.readUnsignedByte();
               var green:int = bytes.readUnsignedByte();
               var red:int = bytes.readUnsignedByte();
               var alpha:int = opaque ? 255 : bytes.readUnsignedByte();
               if(opaque) bytes.position += 1;
               pixels.writeUnsignedInt((alpha << 24) | (red << 16) | (green << 8) | blue);
               x++;
            }
            y++;
         }
         return {"pixels":pixels,"width":width,"height":height};
      }

      private static function compressed(bytes:ByteArray, width:int, height:int, fourCC:String) : Object
      {
         var blocksX:int = (width + 3) >> 2;
         var blocksY:int = (height + 3) >> 2;
         var blockBytes:int = fourCC == "DXT1" ? 8 : 16;
         if(bytes.length < 128 + blocksX * blocksY * blockBytes) return null;
         var pixels:ByteArray = new ByteArray();
         pixels.endian = Endian.BIG_ENDIAN;
         pixels.length = width * height * 4;
         bytes.position = 128;
         var blockY:int = 0;
         while(blockY < blocksY)
         {
            var blockX:int = 0;
            while(blockX < blocksX)
            {
               writeBlock(bytes,pixels,width,height,blockX << 2,blockY << 2,fourCC == "DXT1");
               blockX++;
            }
            blockY++;
         }
         return {"pixels":pixels,"width":width,"height":height};
      }

      private static function writeBlock(bytes:ByteArray, pixels:ByteArray, width:int, height:int, originX:int, originY:int, dxt1:Boolean) : void
      {
         var alpha0:int = 255;
         var alpha1:int = 255;
         var alphaLow:uint = 0;
         var alphaHigh:uint = 0;
         if(!dxt1)
         {
            alpha0 = bytes.readUnsignedByte();
            alpha1 = bytes.readUnsignedByte();
            alphaLow = bytes.readUnsignedInt();
            alphaHigh = bytes.readUnsignedShort();
         }
         var raw0:int = bytes.readUnsignedShort();
         var raw1:int = bytes.readUnsignedShort();
         var color0:uint = color565(raw0);
         var color1:uint = color565(raw1);
         var fourColor:Boolean = !dxt1 || raw0 > raw1;
         var colors:Array = fourColor ? [color0,color1,mix(color0,color1,2,1),mix(color0,color1,1,2)] : [color0,color1,mix(color0,color1,1,1),0];
         var indices:uint = bytes.readUnsignedInt();
         var pixel:int = 0;
         while(pixel < 16)
         {
            var x:int = originX + (pixel & 3);
            var y:int = originY + (pixel >> 2);
            var rgb:uint = uint(colors[(indices >> (pixel * 2)) & 3]);
            var alpha:int = 255;
            if(!dxt1) alpha = alphaValue(alpha0,alpha1,alphaIndex(alphaLow,alphaHigh,pixel));
            else if(!fourColor && ((indices >> (pixel * 2)) & 3) == 3) alpha = 0;
            if(x < width && y < height)
            {
               pixels.position = (y * width + x) << 2;
               pixels.writeUnsignedInt((alpha << 24) | (rgb & 0xFFFFFF));
            }
            pixel++;
         }
      }

      private static function alphaIndex(low:uint, high:uint, pixel:int) : int
      {
         var bit:int = pixel * 3;
         if(bit >= 32) return (high >> (bit - 32)) & 7;
         if(bit <= 29) return (low >> bit) & 7;
         var first:int = 32 - bit;
         return ((low >> bit) & ((1 << first) - 1)) | ((high & ((1 << (3 - first)) - 1)) << first);
      }

      private static function alphaValue(alpha0:int, alpha1:int, code:int) : int
      {
         if(code == 0) return alpha0;
         if(code == 1) return alpha1;
         if(alpha0 > alpha1) return ((8 - code) * alpha0 + (code - 1) * alpha1) / 7;
         if(code == 6) return 0;
         if(code == 7) return 255;
         return ((6 - code) * alpha0 + (code - 1) * alpha1) / 5;
      }

      private static function color565(value:int) : uint
      {
         var red:int = (value >> 11) & 31;
         var green:int = (value >> 5) & 63;
         var blue:int = value & 31;
         red = (red << 3) | (red >> 2);
         green = (green << 2) | (green >> 4);
         blue = (blue << 3) | (blue >> 2);
         return (255 << 24) | (red << 16) | (green << 8) | blue;
      }

      private static function mix(first:uint, second:uint, firstWeight:int, secondWeight:int) : uint
      {
         var divisor:int = firstWeight + secondWeight;
         var alpha:int = ((((first >> 24) & 255) * firstWeight) + (((second >> 24) & 255) * secondWeight)) / divisor;
         var red:int = ((((first >> 16) & 255) * firstWeight) + (((second >> 16) & 255) * secondWeight)) / divisor;
         var green:int = ((((first >> 8) & 255) * firstWeight) + (((second >> 8) & 255) * secondWeight)) / divisor;
         var blue:int = (((first & 255) * firstWeight) + ((second & 255) * secondWeight)) / divisor;
         return (alpha << 24) | (red << 16) | (green << 8) | blue;
      }

      // Called after the plate is on stage. setPixels throws in this player, including when the bitmap was created during a file-load callback.
      public static function upload(width:int, height:int, pixels:ByteArray) : BitmapData
      {
         if(pixels == null || width < 1 || height < 1 || pixels.length < width * height * 4) return null;
         var result:BitmapData = new BitmapData(width,height,true,0);
         if(writePixel32(result,width,height,pixels) || writeFill(result,width,height,pixels)) return result;
         result.dispose();
         return null;
      }

      private static function writePixel32(result:BitmapData, width:int, height:int, pixels:ByteArray) : Boolean
      {
         try
         {
            pixels.endian = Endian.BIG_ENDIAN;
            pixels.position = 0;
            var y:int = 0;
            while(y < height)
            {
               var x:int = 0;
               while(x < width)
               {
                  result.setPixel32(x,y,pixels.readUnsignedInt());
                  x++;
               }
               y++;
            }
            return true;
         }
         catch(pixelError:*)
         {
            return false;
         }
         return false;
      }

      private static function writeFill(result:BitmapData, width:int, height:int, pixels:ByteArray) : Boolean
      {
         try
         {
            pixels.endian = Endian.BIG_ENDIAN;
            pixels.position = 0;
            var dot:Rectangle = new Rectangle(0,0,1,1);
            var y:int = 0;
            while(y < height)
            {
               var x:int = 0;
               while(x < width)
               {
                  dot.x = x;
                  dot.y = y;
                  result.fillRect(dot,pixels.readUnsignedInt());
                  x++;
               }
               y++;
            }
            return true;
         }
         catch(fillError:*)
         {
            return false;
         }
         return false;
      }

      private static function readCode(bytes:ByteArray) : String
      {
         var code:String = "";
         var index:int = 0;
         while(index < 4)
         {
            var charCode:int = bytes.readUnsignedByte();
            if(charCode != 0) code += String.fromCharCode(charCode);
            index++;
         }
         return code;
      }
   }
}
