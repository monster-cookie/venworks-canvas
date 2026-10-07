package
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.geom.ColorTransform;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   // Mip 0 only. Uncompressed A8R8G8B8 and DXT1/DXT5 are returned as pixels. This player does not keep setPixel32 or BitmapData.draw. A crowd of child shapes added during layout did not show. The plate is painted in the panel draw pass: one full fill, then the smoke blocks on a second shape.
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

      // The full fill matches the other HUD fills: one shape, one rectangle. The blocks carry the smoke on a second shape. The tint is baked in.
      public static function paintPlate(parent:Sprite, pixels:ByteArray, pixelWidth:int, pixelHeight:int, originX:Number, originY:Number, destWidth:Number, destHeight:Number, tint:ColorTransform) : Boolean
      {
         if(parent == null || pixels == null || pixelWidth < 1 || pixelHeight < 1 || pixels.length < pixelWidth * pixelHeight * 4) return false;
         if(!(destWidth > 0) || !(destHeight > 0)) return false;
         pixels.endian = Endian.BIG_ENDIAN;
         var redMul:Number = tint == null ? 1 : tint.redMultiplier;
         var greenMul:Number = tint == null ? 1 : tint.greenMultiplier;
         var blueMul:Number = tint == null ? 1 : tint.blueMultiplier;
         var cell:int = 4;
         var plate:Shape = new Shape();
         plate.name = "CanvasStagePaint";
         plate.x = originX;
         plate.y = originY;
         var base:Shape = new Shape();
         base.name = "CanvasStagePaint";
         base.x = originX;
         base.y = originY;
         var painted:Boolean = false;
         var y:int = 0;
         var x:int = 0;
         var cellW:int = 0;
         var cellH:int = 0;
         var py:int = 0;
         var px:int = 0;
         var count:int = 0;
         var alphaSum:Number = 0;
         var redSum:Number = 0;
         var greenSum:Number = 0;
         var blueSum:Number = 0;
         var alphaTotal:Number = 0;
         var redTotal:Number = 0;
         var greenTotal:Number = 0;
         var blueTotal:Number = 0;
         var totalCount:int = 0;
         var argb:uint = 0;
         var alpha:Number = 0;
         var red:int = 0;
         var green:int = 0;
         var blue:int = 0;
         var meanAlpha:Number = 0;
         var meanRed:int = 0;
         var meanGreen:int = 0;
         var meanBlue:int = 0;
         while(y < pixelHeight)
         {
            cellH = pixelHeight - y;
            if(cellH > cell) cellH = cell;
            x = 0;
            while(x < pixelWidth)
            {
               cellW = pixelWidth - x;
               if(cellW > cell) cellW = cell;
               alphaSum = 0;
               redSum = 0;
               greenSum = 0;
               blueSum = 0;
               count = 0;
               py = 0;
               while(py < cellH)
               {
                  px = 0;
                  while(px < cellW)
                  {
                     pixels.position = ((y + py) * pixelWidth + (x + px)) << 2;
                     argb = pixels.readUnsignedInt();
                     alphaSum += (argb >>> 24) & 255;
                     redSum += (argb >>> 16) & 255;
                     greenSum += (argb >>> 8) & 255;
                     blueSum += argb & 255;
                     count++;
                     px++;
                  }
                  py++;
               }
               alphaTotal += alphaSum;
               redTotal += redSum;
               greenTotal += greenSum;
               blueTotal += blueSum;
               totalCount += count;
               alpha = count < 1 ? 0 : alphaSum / count / 255;
               if(alpha > 0)
               {
                  red = int(redSum / count * redMul);
                  green = int(greenSum / count * greenMul);
                  blue = int(blueSum / count * blueMul);
                  if(red < 0) red = 0;
                  else if(red > 255) red = 255;
                  if(green < 0) green = 0;
                  else if(green > 255) green = 255;
                  if(blue < 0) blue = 0;
                  else if(blue > 255) blue = 255;
                  plate.graphics.beginFill((red << 16) | (green << 8) | blue,alpha);
                  plate.graphics.drawRect(x * destWidth / pixelWidth,y * destHeight / pixelHeight,cellW * destWidth / pixelWidth,cellH * destHeight / pixelHeight);
                  plate.graphics.endFill();
                  painted = true;
               }
               x += cellW;
            }
            y += cellH;
         }
         if(!painted || totalCount < 1) return false;
         meanAlpha = alphaTotal / totalCount / 255;
         meanRed = int(redTotal / totalCount * redMul);
         meanGreen = int(greenTotal / totalCount * greenMul);
         meanBlue = int(blueTotal / totalCount * blueMul);
         if(meanRed < 0) meanRed = 0;
         else if(meanRed > 255) meanRed = 255;
         if(meanGreen < 0) meanGreen = 0;
         else if(meanGreen > 255) meanGreen = 255;
         if(meanBlue < 0) meanBlue = 0;
         else if(meanBlue > 255) meanBlue = 255;
         base.graphics.beginFill((meanRed << 16) | (meanGreen << 8) | meanBlue,meanAlpha);
         base.graphics.drawRect(0,0,destWidth,destHeight);
         base.graphics.endFill();
         parent.addChild(base);
         parent.addChild(plate);
         return true;
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
