package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.geom.ColorTransform;
   import flash.net.URLRequest;
   import flash.utils.ByteArray;

   public final class CanvasHtmlResource
   {
      public var path:String;

      public var kind:String;

      public var text:String;

      public var byteLength:int;

      public var document:CanvasHtmlDocument;

      public var image:BitmapData;

      public var pixels:ByteArray;

      public var pixelWidth:int;

      public var pixelHeight:int;

      public var location:String;

      public var loading:Boolean;

      private var watchers:Array;

      private var loader:Loader;

      private var ownsImage:Boolean;

      private var reportedShow:Boolean;

      public function CanvasHtmlResource(param1:String, param2:String, param3:String, param4:int, param5:CanvasHtmlDocument = null)
      {
         this.path = param1;
         this.kind = param2;
         this.text = param3;
         this.byteLength = param4;
         this.document = param5;
      }

      public function takePlate(image:BitmapData, width:int, height:int, owned:Boolean) : void
      {
         if(this.ownsImage && this.image != null && this.image != image) this.image.dispose();
         this.image = image;
         this.pixelWidth = width;
         this.pixelHeight = height;
         this.ownsImage = owned;
         this.pixels = null;
      }

      public function holdLoader(source:Loader) : void
      {
         this.loader = source;
      }

      // Called from the panel draw pass, after that pass clears the previous plate. The log size is the on-screen box, not only the texture.
      public function showPlate(sprite:Sprite, x:Number, y:Number, width:Number, height:Number, tint:ColorTransform) : void
      {
         if(sprite == null || this.pixels == null || this.pixelWidth < 1 || this.pixelHeight < 1) return;
         if(!(width > 0) || !(height > 0)) return;
         var showed:Boolean = CanvasDdsDecoder.paintPlate(sprite,this.pixels,this.pixelWidth,this.pixelHeight,x,y,width,height,tint);
         if(this.reportedShow) return;
         this.reportedShow = true;
         if(showed) this.reportPlate("VWCANVAS TEX SHOW | " + this.path + " | " + this.pixelWidth + "x" + this.pixelHeight + " at " + int(width) + "x" + int(height));
         else this.reportPlate("VWCANVAS TEX SHOW FAIL | " + this.path);
      }

      // Formats this movie cannot decode still use the archive URL the document loader already resolved. The bitmap is sized by the caller because assigning bitmapData resets width and height.
      public function showImage(bitmap:Bitmap, width:Number, height:Number) : void
      {
         if(bitmap == null) return;
         if(this.image != null)
         {
            bitmap.bitmapData = this.image;
            bitmap.width = width;
            bitmap.height = height;
            return;
         }
         if(this.location == null) return;
         if(this.watchers == null) this.watchers = [];
         this.watchers.push({"bitmap":bitmap,"width":width,"height":height});
         if(this.loading) return;
         this.loading = true;
         this.loader = new Loader();
         this.loader.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onImageComplete,false,0,true);
         this.loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onImageError,false,0,true);
         this.loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onImageError,false,0,true);
         try
         {
            this.loader.load(new URLRequest(this.location));
         }
         catch(loadError:*)
         {
            this.onImageError(null);
         }
      }

      public function dispose() : void
      {
         this.text = null;
         this.document = null;
         this.detachPlateFrames();
         this.location = null;
         this.pixels = null;
         if(this.ownsImage && this.image != null) this.image.dispose();
         this.image = null;
         this.ownsImage = false;
         this.releaseLoader(true);
      }

      private function onImageComplete(event:Event) : void
      {
         this.loading = false;
         var source:BitmapData = null;
         try
         {
            var loaded:Bitmap = this.loader == null ? null : this.loader.content as Bitmap;
            if(loaded != null) source = loaded.bitmapData;
         }
         catch(readError:*)
         {
         }
         if(source != null)
         {
            try
            {
               var copy:BitmapData = new BitmapData(source.width,source.height,true,0);
               copy.draw(source);
               this.image = copy;
               this.ownsImage = true;
            }
            catch(copyError:*)
            {
               this.image = source;
               this.ownsImage = false;
            }
         }
         this.publish();
         if(this.ownsImage) this.releaseLoader(true);
      }

      private function onImageError(event:Event) : void
      {
         this.loading = false;
         this.location = null;
         this.watchers = null;
         this.releaseLoader(true);
      }

      private function reportPlate(message:String) : void
      {
         var writer:Function = trace;
         writer(message);
      }

      private function detachPlateFrames() : void
      {
         this.watchers = null;
         this.loading = false;
      }

      private function publish() : void
      {
         if(this.image == null || this.watchers == null) return;
         var watcher:Object = null;
         for each(watcher in this.watchers)
         {
            var bitmap:Bitmap = watcher.bitmap as Bitmap;
            if(bitmap == null) continue;
            bitmap.bitmapData = this.image;
            bitmap.width = Number(watcher.width);
            bitmap.height = Number(watcher.height);
         }
         this.watchers = null;
      }

      private function releaseLoader(unload:Boolean) : void
      {
         if(this.loader == null) return;
         var current:Loader = this.loader;
         this.loader = null;
         try { current.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onImageComplete); } catch(removeComplete:*) {}
         try { current.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onImageError); } catch(removeError:*) {}
         try { current.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onImageError); } catch(removeSecurity:*) {}
         try { current.close(); } catch(closeError:*) {}
         if(unload) { try { current.unload(); } catch(unloadError:*) {} }
      }
   }
}
