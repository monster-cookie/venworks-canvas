package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.InteractiveObject;
   import flash.display.Loader;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.geom.Rectangle;
   import flash.net.URLRequest;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;

   // SymbolLoaderClip.LoadSymbolHelper requests libraryName + ".swf".
   // The installed player HUD passes "WeaponIcons", or the linkage itself when the name begins with CCSUP.
   // The favorites menu uses iconImage.sDirectory and iconImage.sImageName the same way.
   // Canvas host is Interface/venworkscui.swf, so this relative request resolves beside weaponicons.swf.
   // https://pxcnet.xyz/Starfield/Resources/UpdatingPlayerHud/
   public final class CanvasWeaponIcon extends Sprite
   {
      private static const LIBRARY_URL:String = "WeaponIcons.swf";
      private static var libraries:Object = {};
      private var linkage:String;
      private var requestUrl:String;
      private var boxWidth:Number;
      private var boxHeight:Number;
      private var disposed:Boolean = false;

      public static function create(value:*, width:Number, height:Number) : DisplayObject
      {
         var linkage:String = value == null ? "" : String(value);
         var request:String = requestFor(linkage);
         if(request == null || !isFinite(width + height) || width <= 0 || height <= 0 || width > 512 || height > 512) return new Sprite();
         return new CanvasWeaponIcon(linkage,request,width,height);
      }

      public static function requestFor(linkage:String) : String
      {
         if(linkage == null || !/^[A-Za-z0-9_]{1,128}$/.test(linkage)) return null;
         if(linkage.substr(0,5) == "CCSUP") return linkage + ".swf";
         return LIBRARY_URL;
      }

      public function CanvasWeaponIcon(linkage:String, requestUrl:String, width:Number, height:Number)
      {
         super();
         this.linkage = linkage;
         this.requestUrl = requestUrl;
         this.boxWidth = width;
         this.boxHeight = height;
         mouseEnabled = false;
         mouseChildren = false;
         addEventListener(Event.REMOVED_FROM_STAGE,this.onRemoved);
         this.begin();
      }

      private function begin() : void
      {
         var ready:Class = findLoaded(this.linkage);
         if(ready != null)
         {
            this.present(ready);
            return;
         }
         var library:Object = libraries[this.requestUrl];
         if(library == null)
         {
            library = {status:"loading",domain:new ApplicationDomain(ApplicationDomain.currentDomain),loader:new Loader(),waiters:[this]};
            libraries[this.requestUrl] = library;
            var context:LoaderContext = new LoaderContext(false,library.domain as ApplicationDomain);
            library.loader.contentLoaderInfo.addEventListener(Event.COMPLETE,onLibraryLoaded);
            library.loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,onLibraryFailed);
            library.loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,onLibraryFailed);
            try { library.loader.load(new URLRequest(this.requestUrl),context); }
            catch(loadError:*) { failLibrary(library); }
            return;
         }
         if(library.status == "ready") this.present(lookup(library.domain as ApplicationDomain,this.linkage));
         else if(library.status == "loading") library.waiters.push(this);
      }

      private function onRemoved(event:Event) : void
      {
         if(event.target !== this) return;
         this.disposed = true;
         removeEventListener(Event.REMOVED_FROM_STAGE,this.onRemoved);
         removeEventListener(Event.ENTER_FRAME,this.refit);
         var library:Object = libraries[this.requestUrl];
         if(library == null || library.waiters == null) return;
         var remaining:Array = [];
         for each(var waiter:CanvasWeaponIcon in library.waiters) if(waiter !== this && !waiter.disposed) remaining.push(waiter);
         library.waiters = remaining;
      }

      private function present(type:Class) : void
      {
         if(this.disposed || type == null) return;
         var clip:DisplayObject = null;
         try { clip = new type() as DisplayObject; }
         catch(createError:*) { clip = null; }
         if(clip == null) return;
         while(numChildren > 0) removeChildAt(0);
         var interactive:InteractiveObject = clip as InteractiveObject;
         if(interactive != null) interactive.mouseEnabled = false;
         var container:DisplayObjectContainer = clip as DisplayObjectContainer;
         if(container != null) container.mouseChildren = false;
         addChild(clip);
         this.fit(clip);
         addEventListener(Event.ENTER_FRAME,this.refit);
      }

      private function refit(event:Event) : void
      {
         if(event.target !== this) return;
         removeEventListener(Event.ENTER_FRAME,this.refit);
         if(this.disposed || numChildren == 0) return;
         this.fit(getChildAt(0));
      }

      private function fit(clip:DisplayObject) : void
      {
         var measured:DisplayObject = clip;
         var movie:DisplayObjectContainer = clip as DisplayObjectContainer;
         if(movie != null)
         {
            var sizer:DisplayObject = movie.getChildByName("Sizer_mc");
            if(sizer != null) measured = sizer;
         }
         var bounds:Rectangle = measured.getBounds(clip);
         if(bounds.isEmpty() || !isFinite(bounds.x + bounds.y + bounds.width + bounds.height) || bounds.width <= 0 || bounds.height <= 0 || bounds.width > 4096 || bounds.height > 4096) return;
         var scale:Number = Math.min(this.boxWidth / bounds.width,this.boxHeight / bounds.height);
         if(!isFinite(scale) || scale <= 0) return;
         clip.scaleX = scale;
         clip.scaleY = scale;
         clip.x = (this.boxWidth - bounds.width * scale) / 2 - bounds.x * scale;
         clip.y = (this.boxHeight - bounds.height * scale) / 2 - bounds.y * scale;
      }

      private static function onLibraryLoaded(event:Event) : void
      {
         var library:Object = libraryFor(event);
         if(library == null) return;
         library.status = "ready";
         deliver(library);
      }

      private static function onLibraryFailed(event:Event) : void
      {
         var library:Object = libraryFor(event);
         if(library != null) failLibrary(library);
      }

      private static function libraryFor(event:Event) : Object
      {
         var loader:Loader = null;
         try { loader = event.target.loader as Loader; } catch(readError:*) { loader = null; }
         for(var url:String in libraries) if(libraries[url].loader === loader) return libraries[url];
         return null;
      }

      private static function failLibrary(library:Object) : void
      {
         library.status = "failed";
         detach(library);
         library.waiters = [];
      }

      private static function deliver(library:Object) : void
      {
         detach(library);
         var waiters:Array = library.waiters as Array;
         library.waiters = [];
         for each(var waiter:CanvasWeaponIcon in waiters)
         {
            if(waiter == null || waiter.disposed) continue;
            waiter.present(lookup(library.domain as ApplicationDomain,waiter.linkage));
         }
      }

      private static function detach(library:Object) : void
      {
         var loader:Loader = library.loader as Loader;
         if(loader == null) return;
         try { loader.contentLoaderInfo.removeEventListener(Event.COMPLETE,onLibraryLoaded); } catch(completeError:*) {}
         try { loader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,onLibraryFailed); } catch(errorError:*) {}
         try { loader.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,onLibraryFailed); } catch(securityError:*) {}
      }

      private static function findLoaded(linkage:String) : Class
      {
         var defined:Class = lookup(ApplicationDomain.currentDomain,linkage);
         if(defined != null) return defined;
         for(var url:String in libraries)
         {
            var library:Object = libraries[url];
            if(library.status != "ready") continue;
            defined = lookup(library.domain as ApplicationDomain,linkage);
            if(defined != null) return defined;
         }
         return null;
      }

      private static function lookup(domain:ApplicationDomain, linkage:String) : Class
      {
         if(domain == null) return null;
         try { if(domain.hasDefinition(linkage)) return domain.getDefinition(linkage) as Class; }
         catch(lookupError:*) {}
         return null;
      }
   }
}
