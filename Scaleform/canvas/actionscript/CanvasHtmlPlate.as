package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.ColorTransform;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   // Built when the sprite joins the stage. Assigning bitmap width threw TypeError 2077, the filter-parameter error. The sprite scale covers the plate.
   public final class CanvasHtmlPlate extends Sprite
   {
      private static var reported:Boolean = false;

      private var pixels:ByteArray;

      private var pixelWidth:int;

      private var pixelHeight:int;

      private var plateWidth:Number;

      private var plateHeight:Number;

      private var redMul:Number;

      private var greenMul:Number;

      private var blueMul:Number;

      private var opacity:Number;

      private var image:BitmapData;

      private var bitmap:Bitmap;

      private var baked:ByteArray;

      private var solid:uint;

      private var meanAlpha:int;

      private var scaleNote:String = "scaled";

      public function CanvasHtmlPlate(pixels:ByteArray, pixelWidth:int, pixelHeight:int, plateWidth:Number, plateHeight:Number, tint:ColorTransform, opacity:Number)
      {
         this.pixels = pixels;
         this.pixelWidth = pixelWidth;
         this.pixelHeight = pixelHeight;
         this.plateWidth = plateWidth;
         this.plateHeight = plateHeight;
         this.redMul = tint == null ? 1 : tint.redMultiplier;
         this.greenMul = tint == null ? 1 : tint.greenMultiplier;
         this.blueMul = tint == null ? 1 : tint.blueMultiplier;
         this.opacity = opacity;
         this.mouseEnabled = false;
         this.mouseChildren = false;
         this.name = "CanvasStagePaint";
         addEventListener(Event.ADDED_TO_STAGE,this.onStage);
         addEventListener(Event.REMOVED_FROM_STAGE,this.onRemove);
      }

      private function onStage(event:Event) : void
      {
         if(event.target !== this || this.bitmap != null) return;
         if(this.pixels == null || this.pixelWidth < 1 || this.pixelHeight < 1 || this.pixels.length < this.pixelWidth * this.pixelHeight * 4)
         {
            this.report("VWCANVAS TEX BITMAP FAIL | short");
            return;
         }
         try
         {
            this.baked = this.bake();
         }
         catch(bakeError:*)
         {
            this.report("VWCANVAS TEX BITMAP FAIL | bake " + String(bakeError));
            return;
         }
         var data:BitmapData = null;
         try
         {
            data = new BitmapData(this.pixelWidth,this.pixelHeight,true,0);
         }
         catch(dataError:*)
         {
            this.report("VWCANVAS TEX BITMAP FAIL | data " + String(dataError));
            return;
         }
         var view:Bitmap = null;
         try
         {
            view = new Bitmap(data,"auto",false);
         }
         catch(viewError:*)
         {
            data.dispose();
            this.report("VWCANVAS TEX BITMAP FAIL | view " + String(viewError));
            return;
         }
         this.image = data;
         this.bitmap = view;
         try
         {
            this.scaleX = this.plateWidth / this.pixelWidth;
            this.scaleY = this.plateHeight / this.pixelHeight;
         }
         catch(scaleError:*)
         {
            this.scaleNote = "unscaled";
         }
         try
         {
            addChild(view);
         }
         catch(childError:*)
         {
            this.report("VWCANVAS TEX BITMAP FAIL | child " + String(childError));
            return;
         }
         addEventListener(Event.ENTER_FRAME,this.onFrame);
      }

      private function onFrame(event:Event) : void
      {
         removeEventListener(Event.ENTER_FRAME,this.onFrame);
         if(this.image == null || this.baked == null) return;
         var mode:String = "solid";
         try
         {
            this.baked.position = 0;
            this.image.setPixels(this.image.rect,this.baked);
            mode = "pixels";
         }
         catch(pixelError:*)
         {
            try
            {
               this.image.fillRect(this.image.rect,this.solid);
            }
            catch(fillError:*)
            {
               this.baked = null;
               this.report("VWCANVAS TEX BITMAP FAIL | pixels " + String(pixelError) + " | fill " + String(fillError));
               return;
            }
         }
         this.baked = null;
         this.report("VWCANVAS TEX BITMAP | " + this.pixelWidth + "x" + this.pixelHeight + " alpha " + this.meanAlpha + " pos " + int(this.x) + "," + int(this.y) + " " + this.scaleNote + " " + mode);
      }

      private function bake() : ByteArray
      {
         var count:int = this.pixelWidth * this.pixelHeight;
         var output:ByteArray = new ByteArray();
         output.endian = Endian.BIG_ENDIAN;
         output.length = count * 4;
         this.pixels.endian = Endian.BIG_ENDIAN;
         var alphaTotal:Number = 0;
         var redTotal:Number = 0;
         var greenTotal:Number = 0;
         var blueTotal:Number = 0;
         var index:int = 0;
         while(index < count)
         {
            this.pixels.position = index << 2;
            var argb:uint = this.pixels.readUnsignedInt();
            var sourceAlpha:int = (argb >>> 24) & 255;
            var alpha:int = int(sourceAlpha * this.opacity);
            var red:int = int(((argb >>> 16) & 255) * this.redMul);
            var green:int = int(((argb >>> 8) & 255) * this.greenMul);
            var blue:int = int((argb & 255) * this.blueMul);
            if(alpha < 0) alpha = 0;
            else if(alpha > 255) alpha = 255;
            if(red < 0) red = 0;
            else if(red > 255) red = 255;
            if(green < 0) green = 0;
            else if(green > 255) green = 255;
            if(blue < 0) blue = 0;
            else if(blue > 255) blue = 255;
            output.position = index << 2;
            output.writeUnsignedInt(uint((alpha << 24) | (red << 16) | (green << 8) | blue));
            alphaTotal += sourceAlpha;
            redTotal += red;
            greenTotal += green;
            blueTotal += blue;
            index++;
         }
         var averageAlpha:int = count < 1 ? 0 : int(alphaTotal / count * this.opacity);
         var averageRed:int = count < 1 ? 0 : int(redTotal / count);
         var averageGreen:int = count < 1 ? 0 : int(greenTotal / count);
         var averageBlue:int = count < 1 ? 0 : int(blueTotal / count);
         if(averageAlpha < 0) averageAlpha = 0;
         else if(averageAlpha > 255) averageAlpha = 255;
         if(averageRed < 0) averageRed = 0;
         else if(averageRed > 255) averageRed = 255;
         if(averageGreen < 0) averageGreen = 0;
         else if(averageGreen > 255) averageGreen = 255;
         if(averageBlue < 0) averageBlue = 0;
         else if(averageBlue > 255) averageBlue = 255;
         this.solid = uint((averageAlpha << 24) | (averageRed << 16) | (averageGreen << 8) | averageBlue);
         this.meanAlpha = count < 1 ? 0 : int(alphaTotal / count);
         output.position = 0;
         return output;
      }

      private function report(message:String) : void
      {
         if(CanvasHtmlPlate.reported) return;
         CanvasHtmlPlate.reported = true;
         var writer:Function = trace;
         writer(message);
      }

      private function onRemove(event:Event) : void
      {
         if(event.target !== this || this.bitmap == null) return;
         removeEventListener(Event.ENTER_FRAME,this.onFrame);
         if(this.bitmap.parent === this) removeChild(this.bitmap);
         if(this.image != null) this.image.dispose();
         this.bitmap = null;
         this.image = null;
         this.baked = null;
      }
   }
}
