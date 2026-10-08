package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.ColorTransform;
   import flash.geom.Rectangle;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   // Built when the sprite joins the stage. Fills drawn during layout did not remain on screen.
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
         try
         {
            if(this.pixels == null || this.pixelWidth < 1 || this.pixelHeight < 1 || this.pixels.length < this.pixelWidth * this.pixelHeight * 4)
            {
               this.report("VWCANVAS TEX BITMAP FAIL | short");
               return;
            }
            var data:BitmapData = new BitmapData(this.pixelWidth,this.pixelHeight,true,0);
            var rect:Rectangle = new Rectangle(0,0,1,1);
            var alphaTotal:Number = 0;
            var count:int = 0;
            this.pixels.endian = Endian.BIG_ENDIAN;
            var y:int = 0;
            while(y < this.pixelHeight)
            {
               var x:int = 0;
               while(x < this.pixelWidth)
               {
                  this.pixels.position = ((y * this.pixelWidth) + x) << 2;
                  var argb:uint = this.pixels.readUnsignedInt();
                  var alpha:int = int(((argb >>> 24) & 255) * this.opacity);
                  if(alpha < 0) alpha = 0;
                  else if(alpha > 255) alpha = 255;
                  var red:int = int(((argb >>> 16) & 255) * this.redMul);
                  var green:int = int(((argb >>> 8) & 255) * this.greenMul);
                  var blue:int = int((argb & 255) * this.blueMul);
                  if(red < 0) red = 0;
                  else if(red > 255) red = 255;
                  if(green < 0) green = 0;
                  else if(green > 255) green = 255;
                  if(blue < 0) blue = 0;
                  else if(blue > 255) blue = 255;
                  rect.x = x;
                  rect.y = y;
                  data.fillRect(rect,uint((alpha << 24) | (red << 16) | (green << 8) | blue));
                  alphaTotal += (argb >>> 24) & 255;
                  count++;
                  x++;
               }
               y++;
            }
            var view:Bitmap = new Bitmap(data,"auto",true);
            view.width = this.plateWidth;
            view.height = this.plateHeight;
            this.image = data;
            this.bitmap = view;
            addChild(view);
            this.report("VWCANVAS TEX BITMAP | " + this.pixelWidth + "x" + this.pixelHeight + " alpha " + (count < 1 ? 0 : int(alphaTotal / count)) + " pos " + int(this.x) + "," + int(this.y));
         }
         catch(error:*)
         {
            this.report("VWCANVAS TEX BITMAP FAIL | " + String(error));
         }
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
         if(this.bitmap.parent === this) removeChild(this.bitmap);
         if(this.image != null) this.image.dispose();
         this.bitmap = null;
         this.image = null;
      }
   }
}
