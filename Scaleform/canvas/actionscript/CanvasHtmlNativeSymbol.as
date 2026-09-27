package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.utils.getDefinitionByName;

   // Only host-owned, explicitly named artwork is exposed. Native controls never move.
   public final class CanvasHtmlNativeSymbol extends Sprite
   {
      private var resolve:Function;
      private var pixels:BitmapData;
      private var bitmap:Bitmap;
      private var outputWidth:int;
      private var outputHeight:int;

      public static function allowed(name:String) : Boolean
      {
         return ["vehicle-exit-prompt","weapon-icon","compass-marker"].indexOf(name) >= 0;
      }

      public static function valid(name:String, value:*) : Boolean
      {
         if(!allowed(name)) return false;
         if(name != "compass-marker") return value == null || typeof value == "string" && String(value).length <= 128;
         if(value == null) return true;
         for each(var field:String in ["type","relative","subcategory","locationtype","locationcategory","locationstate"])
         {
            CanvasHtmlData.access = "symbol.valid." + name + "." + field;
            var limit:int = field == "type" ? 255 : field == "relative" || field == "subcategory" ? 3 : 65535;
            if(typeof value[field] != "number" || !isFinite(Number(value[field])) || value[field] != int(value[field]) || value[field] < 0 || value[field] > limit) return false;
         }
         CanvasHtmlData.access = "symbol.valid." + name + ".effect";
         return typeof value.effect == "string" && /^[A-Za-z0-9_-]{0,96}$/.test(String(value.effect));
      }

      public static function marker(value:Object) : DisplayObject
      {
         if(value == null) return new Sprite();
         try
         {
            CanvasHtmlData.access = "symbol.marker.define";
            var type:Class = getDefinitionByName("CompassMarkerWidget") as Class;
            var utility:Class = getDefinitionByName("Shared.MapMarkerUtils") as Class;
            CanvasHtmlData.access = "symbol.marker.create";
            var marker:MovieClip = new type() as MovieClip;
            marker.mouseEnabled = false; marker.mouseChildren = false;
            CanvasHtmlData.access = "symbol.marker.frame";
            marker.gotoAndStop(utility["GetMajorFrameFromMitMarkerType"](uint(value.type)));
            CanvasHtmlData.access = "symbol.marker.location";
            if(value.type == 7) Object(marker)["SetLocation"](value.locationtype,value.locationcategory,value.locationstate);
            else Object(marker)["ClearLocation"]();
            CanvasHtmlData.access = "symbol.marker.relative";
            if(value.relative > 0) Object(marker)["SetFrame"](["","BelowPlayer","LevelWithPlayer","AbovePlayer"][value.relative],false);
            CanvasHtmlData.access = "symbol.marker.category";
            if(value.subcategory > 0) Object(marker)["SetFrame"](["","Undiscovered","Discovered","Targeted"][value.subcategory],true);
            CanvasHtmlData.access = "symbol.marker.effect";
            if(value.effect != "") MovieClip(Object(marker)["MarkerIcon_mc"]).gotoAndStop(String(value.effect));
            return marker;
         }
         catch(markerError:*)
         {
            var fallback:Sprite = new Sprite();
            fallback.graphics.beginFill(0xF4FBFF,1);
            fallback.graphics.drawCircle(0,0,4);
            fallback.graphics.endFill();
            return fallback;
         }
         return new Sprite();
      }

      public function CanvasHtmlNativeSymbol(resolver:Function, width:Number, height:Number)
      {
         if(resolver == null || !isFinite(width+height) || width <= 0 || height <= 0 || width > 512 || height > 512) throw new Error("Invalid native symbol bounds");
         this.resolve = resolver;
         this.outputWidth = Math.ceil(width); this.outputHeight = Math.ceil(height);
         mouseEnabled = false; mouseChildren = false;
         addEventListener(Event.ADDED_TO_STAGE,this.start);
         addEventListener(Event.REMOVED_FROM_STAGE,this.stop);
      }

      private function start(event:Event) : void
      {
         if(event.target !== this) return;
         this.pixels = new BitmapData(this.outputWidth,this.outputHeight,true,0);
         this.bitmap = new Bitmap(this.pixels,"auto",true);
         addChild(this.bitmap);
         addEventListener(Event.ENTER_FRAME,this.refresh,false,-1000,false);
         this.refresh(null);
      }

      private function stop(event:Event) : void
      {
         if(event.target !== this) return;
         removeEventListener(Event.ENTER_FRAME,this.refresh);
         if(this.bitmap != null && this.bitmap.parent === this) removeChild(this.bitmap);
         if(this.pixels != null) this.pixels.dispose();
         this.bitmap = null; this.pixels = null;
      }

      private function refresh(event:Event) : void
      {
         if(this.pixels == null) return;
         for(var ancestor:DisplayObject = this; ancestor != null; ancestor = ancestor.parent)
            if(!ancestor.visible || ancestor.alpha == 0) return;
         this.pixels.fillRect(this.pixels.rect,0);
         var source:DisplayObject = this.resolve() as DisplayObject;
         if(source == null) return;
         for(var sourceAncestor:DisplayObject = source; sourceAncestor != null; sourceAncestor = sourceAncestor.parent)
            if(!sourceAncestor.visible || sourceAncestor.alpha == 0) return;
         var bounds:Rectangle = source.getBounds(source);
         if(bounds.isEmpty() || !isFinite(bounds.x+bounds.y+bounds.width+bounds.height) || bounds.width > 4096 || bounds.height > 4096) return;
         var scale:Number = Math.min(this.outputWidth/bounds.width,this.outputHeight/bounds.height);
         var matrix:Matrix = new Matrix(scale,0,0,scale,(this.outputWidth-bounds.width*scale)/2-bounds.x*scale,(this.outputHeight-bounds.height*scale)/2-bounds.y*scale);
         try { this.pixels.draw(source,matrix,null,null,null,true); }
         catch(error:*) { this.pixels.fillRect(this.pixels.rect,0); trace("VWCANVAS NATIVE SYMBOL | capture unavailable"); removeEventListener(Event.ENTER_FRAME,this.refresh); }
      }
   }
}
