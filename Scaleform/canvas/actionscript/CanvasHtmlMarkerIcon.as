package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.Matrix;

   // Paints a CompassMarkerWidget that must never join the document. The compass wrapper supplies position, scale, and opacity.
   public final class CanvasHtmlMarkerIcon extends Sprite
   {
      private static const FRAME:int = 96;

      private var widget:MovieClip;
      private var pixels:BitmapData;
      private var bitmap:Bitmap;
      private var frames:int;
      private var quiet:int;

      public function CanvasHtmlMarkerIcon(widget:MovieClip)
      {
         super();
         this.widget = widget;
         mouseEnabled = false;
         mouseChildren = false;
         addEventListener(Event.ADDED_TO_STAGE,this.start);
         addEventListener(Event.REMOVED_FROM_STAGE,this.stop);
      }

      private function start(event:Event) : void
      {
         if(event.target !== this || this.widget == null) return;
         removeEventListener(Event.ENTER_FRAME,this.redraw);
         addEventListener(Event.ENTER_FRAME,this.redraw,false,-1000,false);
      }

      private function stop(event:Event) : void
      {
         if(event.target !== this) return;
         removeEventListener(Event.ENTER_FRAME,this.redraw);
      }

      private function redraw(event:Event) : void
      {
         if(this.widget == null) return;
         if(this.pixels == null)
         {
            this.pixels = new BitmapData(FRAME,FRAME,true,0);
            this.bitmap = new Bitmap(this.pixels,"auto",true);
            this.bitmap.x = -FRAME / 2;
            this.bitmap.y = -FRAME / 2;
            addChild(this.bitmap);
         }
         else this.pixels.fillRect(this.pixels.rect,0);
         try { this.pixels.draw(this.widget,new Matrix(1,0,0,1,FRAME / 2,FRAME / 2),null,null,null,true); }
         catch(drawError:*)
         {
            this.pixels.fillRect(this.pixels.rect,0);
            removeEventListener(Event.ENTER_FRAME,this.redraw);
            return;
         }
         this.frames++;
         var settled:Boolean = false;
         try { settled = ("needsLocationLoaded" in this.widget) && !Boolean(this.widget["needsLocationLoaded"]); }
         catch(readyError:*) { settled = false; }
         this.quiet = settled ? this.quiet + 1 : 0;
         if(this.quiet > 15 || this.frames > 300) removeEventListener(Event.ENTER_FRAME,this.redraw);
      }
   }
}
