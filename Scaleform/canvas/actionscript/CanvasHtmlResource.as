package
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.Loader;
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

      public function CanvasHtmlResource(param1:String, param2:String, param3:String, param4:int, param5:CanvasHtmlDocument = null)
      {
         this.path = param1;
         this.kind = param2;
         this.text = param3;
         this.byteLength = param4;
         this.document = param5;
      }

      // The plate bitmap is sized after bitmapData is assigned because that assignment resets width and height. Upload waits for a frame so it is not inside the file callback.
      public function showPlate(bitmap:Bitmap, host:DisplayObject, width:Number, height:Number, tint:ColorTransform) : void
      {
         if(bitmap == null) return;
         if(this.image != null)
         {
            this.applyPlate(bitmap,width,height,tint);
            return;
         }
         if(host == null || this.pixels == null || this.pixelWidth < 1 || this.pixelHeight < 1) return;
         if(this.watchers == null) this.watchers = [];
         this.watchers.push({"bitmap":bitmap,"host":host,"width":width,"height":height,"tint":tint});
         host.addEventListener(Event.ENTER_FRAME,this.onPlateFrame,false,0,true);
         this.loading = true;
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

      private function onPlateFrame(event:Event) : void
      {
         var source:DisplayObject = event.currentTarget as DisplayObject;
         if(source != null) source.removeEventListener(Event.ENTER_FRAME,this.onPlateFrame);
         if(this.image == null && this.pixels != null)
         {
            var uploaded:BitmapData = null;
            try { uploaded = CanvasDdsDecoder.upload(this.pixelWidth,this.pixelHeight,this.pixels); }
            catch(uploadError:*) { uploaded = null; }
            this.pixels = null;
            this.image = uploaded;
            this.ownsImage = uploaded != null;
         }
         if(this.watchers == null) return;
         var pending:Array = this.watchers;
         this.watchers = null;
         this.loading = false;
         var watcher:Object = null;
         for each(watcher in pending)
         {
            var host:DisplayObject = watcher.host as DisplayObject;
            if(host != null && host != source) host.removeEventListener(Event.ENTER_FRAME,this.onPlateFrame);
            this.applyPlate(watcher.bitmap as Bitmap,Number(watcher.width),Number(watcher.height),watcher.tint as ColorTransform);
         }
      }

      private function applyPlate(bitmap:Bitmap, width:Number, height:Number, tint:ColorTransform) : void
      {
         if(bitmap == null || this.image == null) return;
         bitmap.bitmapData = this.image;
         bitmap.width = width;
         bitmap.height = height;
         if(tint == null) return;
         try { bitmap.transform.colorTransform = tint; }
         catch(tintError:*) {}
      }

      private function detachPlateFrames() : void
      {
         if(this.watchers == null) return;
         var watcher:Object = null;
         for each(watcher in this.watchers)
         {
            var host:DisplayObject = watcher.host as DisplayObject;
            if(host != null) host.removeEventListener(Event.ENTER_FRAME,this.onPlateFrame);
         }
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
