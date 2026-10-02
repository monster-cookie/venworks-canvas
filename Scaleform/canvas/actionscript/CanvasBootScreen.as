package
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.text.TextFormatAlign;

   // Centered Player HUD boot mark. The arc spins until the host dismisses it.
   public final class CanvasBootScreen extends Sprite
   {
      public static const LABEL:String = "VENWORKS CANVAS OS BOOTING";

      private static const HALF_WIDTH:Number = 380;

      private static const HALF_HEIGHT:Number = 176;

      private static const DISC_COLOR:uint = 0x0B1E33;

      private static const MARK_COLOR:uint = 0xD7E7EE;

      private static const ARC_COLOR:uint = 0x35E4FF;

      private static const TRACK_COLOR:uint = 0x16384A;

      private static const TEXT_COLOR:uint = 0x4FE7FF;

      private var spinner:Shape;

      private var frameHandler:Function;

      public function CanvasBootScreen()
      {
         super();
         mouseEnabled = false;
         mouseChildren = false;
         this.drawMark();
         this.drawLabel();
         this.frameHandler = this.onFrame;
         addEventListener(Event.ENTER_FRAME,this.frameHandler,false,0,false);
      }

      public function place(param1:Object) : void
      {
         var visibleX:Number = 0;
         var visibleY:Number = 0;
         var visibleWidth:Number = CanvasStageGuard.screenWidth;
         var visibleHeight:Number = CanvasStageGuard.screenHeight;
         var centerX:Number = 0;
         var centerY:Number = 0;
         var minX:Number = 0;
         var maxX:Number = 0;
         var minY:Number = 0;
         var maxY:Number = 0;
         if(param1 != null && !(param1 is Array) && typeof param1 == "object")
         {
            visibleX = this.layoutNumber(param1,"visibleX",visibleX);
            visibleY = this.layoutNumber(param1,"visibleY",visibleY);
            visibleWidth = this.layoutNumber(param1,"visibleWidth",visibleWidth);
            visibleHeight = this.layoutNumber(param1,"visibleHeight",visibleHeight);
         }
         if(!(visibleWidth > 0))
         {
            visibleWidth = CanvasStageGuard.screenWidth;
         }
         if(!(visibleHeight > 0))
         {
            visibleHeight = CanvasStageGuard.screenHeight;
         }
         centerX = visibleX + visibleWidth * 0.5;
         centerY = visibleY + visibleHeight * 0.5;
         minX = HALF_WIDTH;
         maxX = CanvasStageGuard.screenWidth - HALF_WIDTH;
         minY = HALF_HEIGHT;
         maxY = CanvasStageGuard.screenHeight - HALF_HEIGHT;
         x = maxX < minX ? CanvasStageGuard.screenWidth * 0.5 : Math.max(minX,Math.min(maxX,centerX));
         y = maxY < minY ? CanvasStageGuard.screenHeight * 0.5 : Math.max(minY,Math.min(maxY,centerY));
      }

      public function dismiss() : void
      {
         if(this.frameHandler != null)
         {
            removeEventListener(Event.ENTER_FRAME,this.frameHandler);
            this.frameHandler = null;
         }
         if(this.parent != null)
         {
            this.parent.removeChild(this);
         }
      }

      private function onFrame(param1:Event) : void
      {
         if(this.spinner != null)
         {
            this.spinner.rotation = (this.spinner.rotation + 6) % 360;
         }
      }

      private function drawMark() : void
      {
         var mark:Shape = new Shape();
         mark.graphics.beginFill(DISC_COLOR);
         mark.graphics.drawCircle(0,0,90);
         mark.graphics.endFill();
         mark.graphics.lineStyle(3,TRACK_COLOR,1,true);
         mark.graphics.drawCircle(0,0,78);
         mark.graphics.lineStyle(8,TRACK_COLOR,1,true);
         mark.graphics.drawCircle(0,0,104);
         mark.graphics.lineStyle();
         this.drawStar(mark,0,-46,11,4);
         mark.graphics.lineStyle();
         mark.graphics.beginFill(MARK_COLOR);
         mark.graphics.moveTo(-40,-30);
         mark.graphics.lineTo(-18,-30);
         mark.graphics.lineTo(0,16);
         mark.graphics.lineTo(18,-30);
         mark.graphics.lineTo(40,-30);
         mark.graphics.lineTo(8,42);
         mark.graphics.lineTo(-8,42);
         mark.graphics.endFill();
         mark.graphics.lineStyle(6,MARK_COLOR,1,true);
         this.drawArc(mark,58,24,250);
         addChild(mark);
         this.spinner = new Shape();
         this.spinner.graphics.lineStyle(8,ARC_COLOR,1,true);
         this.drawArc(this.spinner,104,-40,292);
         addChild(this.spinner);
      }

      private function drawLabel() : void
      {
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",22,TEXT_COLOR,false);
         var label:TextField = new TextField();
         format.align = TextFormatAlign.CENTER;
         format.letterSpacing = 3;
         label.x = -360;
         label.y = 122;
         label.width = 720;
         label.height = 36;
         label.embedFonts = true;
         label.selectable = false;
         label.mouseEnabled = false;
         label.defaultTextFormat = format;
         label.text = LABEL;
         label.setTextFormat(format);
         addChild(label);
      }

      private function drawStar(param1:Shape, param2:Number, param3:Number, param4:Number, param5:Number) : void
      {
         var index:int = 0;
         var radius:Number = 0;
         var angle:Number = 0;
         param1.graphics.beginFill(ARC_COLOR);
         param1.graphics.moveTo(param2,param3 - param4);
         while(index < 8)
         {
            index++;
            radius = index % 2 == 0 ? param4 : param5;
            angle = -Math.PI / 2 + index * Math.PI / 4;
            param1.graphics.lineTo(param2 + Math.cos(angle) * radius,param3 + Math.sin(angle) * radius);
         }
         param1.graphics.endFill();
      }

      private function drawArc(param1:Shape, param2:Number, param3:Number, param4:Number) : void
      {
         var steps:int = Math.max(1,Math.ceil(Math.abs(param4) / 6));
         var index:int = 0;
         var radians:Number = param3 * Math.PI / 180;
         if(Math.abs(param4) <= 0)
         {
            return;
         }
         param1.graphics.moveTo(Math.cos(radians) * param2,Math.sin(radians) * param2);
         while(index < steps)
         {
            index++;
            radians = (param3 + param4 * index / steps) * Math.PI / 180;
            param1.graphics.lineTo(Math.cos(radians) * param2,Math.sin(radians) * param2);
         }
      }

      private function layoutNumber(param1:Object, param2:String, param3:Number) : Number
      {
         var value:Number = NaN;
         if(!(param2 in param1) || typeof param1[param2] != "number")
         {
            return param3;
         }
         value = Number(param1[param2]);
         return isFinite(value) ? value : param3;
      }
   }
}
