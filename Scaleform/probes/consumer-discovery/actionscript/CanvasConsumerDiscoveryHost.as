package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLRequest;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasConsumerDiscoveryHost extends MovieClip
   {
      private static const PROTOCOL:String = "VWCANVAS_DISCOVERY_PROBE/1";
      private static const SLOT_COUNT:int = 4;
      private static const SLOT_ROOT:String = "VenworksCanvas/Consumers/";

      private var owner:DisplayObjectContainer;
      private var diagnostics:TextField;
      private var diagnosticLines:Array;
      private var loaders:Array;
      private var bridges:Array;
      private var slotStates:Array;
      private var currentLoader:Loader;
      private var currentBridge:Object;
      private var currentSlot:int;
      private var currentPath:String;
      private var displayMode:String;
      private var readyCount:int;
      private var disposed:Boolean = true;

      public function initialize(param1:DisplayObjectContainer) : void
      {
         this.dispose();
         this.disposed = false;
         this.owner = param1;
         this.diagnosticLines = [];
         this.loaders = [];
         this.bridges = [];
         this.slotStates = [];
         this.currentSlot = -1;
         this.currentPath = "";
         this.readyCount = 0;
         this.displayMode = this.resolveDisplayMode(param1);
         addEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage,false,0,true);
         this.createDiagnostics();
         this.appendDiagnostic("VWCANVAS-9 FIXED-SLOT PROBE");
         this.appendDiagnostic("MODE " + this.displayMode.toUpperCase() + " | OWNER " + this.resolveOwnerUrl(param1));
         this.discoverNextSlot();
      }

      public function reapplyVanillaPlacements() : void
      {
         if(this.diagnostics != null)
         {
            this.diagnostics.x = 500;
            this.diagnostics.y = 150;
         }
      }

      public function updateVanillaHudModeVisibility(param1:Array) : void
      {
      }

      public function dispose() : void
      {
         var index:int = 0;
         var bridge:Object = null;
         var loader:Loader = null;
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         removeEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage);
         this.removeCurrentLoaderListeners();
         for(index = 0; index < this.bridges.length; index++)
         {
            bridge = this.bridges[index];
            if(bridge != null && "dispose" in bridge)
            {
               try
               {
                  bridge["dispose"]();
               }
               catch(bridgeDisposeError:Error)
               {
               }
            }
         }
         for(index = 0; index < this.loaders.length; index++)
         {
            loader = this.loaders[index] as Loader;
            if(loader == null)
            {
               continue;
            }
            if(loader.parent === this)
            {
               removeChild(loader);
            }
            try
            {
               loader.close();
            }
            catch(loaderCloseError:Error)
            {
            }
            try
            {
               loader.unload();
            }
            catch(loaderUnloadError:Error)
            {
            }
         }
         if(this.diagnostics != null && this.diagnostics.parent === this)
         {
            removeChild(this.diagnostics);
         }
         this.currentLoader = null;
         this.currentBridge = null;
         this.owner = null;
         this.diagnostics = null;
         this.diagnosticLines = null;
         this.loaders = null;
         this.bridges = null;
         this.slotStates = null;
      }

      private function discoverNextSlot() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.currentSlot++;
         if(this.currentSlot >= SLOT_COUNT)
         {
            this.appendDiagnostic("COMPLETE | READY " + this.readyCount + "/" + SLOT_COUNT);
            return;
         }
         this.currentPath = SLOT_ROOT + this.displayMode + "/" + this.formatSlot(this.currentSlot) + ".swf";
         this.slotStates[this.currentSlot] = "requesting";
         this.appendDiagnostic(this.formatSlot(this.currentSlot).toUpperCase() + " REQUEST " + this.currentPath);
         this.currentBridge = null;
         this.currentLoader = new Loader();
         this.loaders.push(this.currentLoader);
         this.currentLoader.contentLoaderInfo.addEventListener(Event.INIT,this.onConsumerInit,false,0,true);
         this.currentLoader.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onConsumerComplete,false,0,true);
         this.currentLoader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onConsumerIoError,false,0,true);
         this.currentLoader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onConsumerSecurityError,false,0,true);
         try
         {
            this.currentLoader.load(new URLRequest(this.currentPath));
         }
         catch(loadError:Error)
         {
            this.finishCurrentFailure("LOAD",loadError.toString());
         }
      }

      private function onConsumerInit(param1:Event) : void
      {
         var content:DisplayObject = null;
         var record:Object = null;
         if(this.disposed || this.currentLoader == null)
         {
            return;
         }
         try
         {
            content = this.currentLoader.content;
            this.currentBridge = content as Object;
            if(this.currentBridge == null || !("getCanvasDiscoveryRecord" in this.currentBridge))
            {
               throw new Error("missing getCanvasDiscoveryRecord()");
            }
            record = this.currentBridge["getCanvasDiscoveryRecord"]();
            this.validateRecord(record);
         }
         catch(validationError:Error)
         {
            this.finishCurrentFailure("INVALID",validationError.toString());
         }
      }

      private function onConsumerComplete(param1:Event) : void
      {
         var record:Object = null;
         var observedPath:String = null;
         if(this.disposed || this.currentLoader == null || this.currentBridge == null)
         {
            return;
         }
         try
         {
            record = this.currentBridge["getCanvasDiscoveryRecord"]();
            this.validateRecord(record);
            observedPath = this.sanitizeText(this.currentLoader.contentLoaderInfo.url,160);
            this.removeCurrentLoaderListeners();
            addChild(this.currentLoader);
            this.bridges.push(this.currentBridge);
            this.slotStates[this.currentSlot] = "ready";
            this.readyCount++;
            this.appendDiagnostic(this.formatSlot(this.currentSlot).toUpperCase() + " READY | " +
               this.sanitizeText(record["consumerId"],48) + " | " +
               this.sanitizeText(record["version"],24) + " | " +
               this.sanitizeText(record["marker"],24));
            this.appendDiagnostic("  URL " + observedPath);
            this.currentLoader = null;
            this.currentBridge = null;
            this.discoverNextSlot();
         }
         catch(completionError:Error)
         {
            this.finishCurrentFailure("COMPLETE",completionError.toString());
         }
      }

      private function onConsumerIoError(param1:IOErrorEvent) : void
      {
         this.finishCurrentFailure("MISSING",param1.toString());
      }

      private function onConsumerSecurityError(param1:SecurityErrorEvent) : void
      {
         this.finishCurrentFailure("SECURITY",param1.toString());
      }

      private function finishCurrentFailure(param1:String, param2:String) : void
      {
         var failedLoader:Loader = this.currentLoader;
         if(this.disposed || failedLoader == null)
         {
            return;
         }
         this.removeCurrentLoaderListeners();
         this.slotStates[this.currentSlot] = param1.toLowerCase();
         this.appendDiagnostic(this.formatSlot(this.currentSlot).toUpperCase() + " " + param1 + " | " + this.sanitizeText(param2,120));
         try
         {
            failedLoader.close();
         }
         catch(closeError:Error)
         {
         }
         try
         {
            failedLoader.unload();
         }
         catch(unloadError:Error)
         {
         }
         this.currentLoader = null;
         this.currentBridge = null;
         this.discoverNextSlot();
      }

      private function validateRecord(param1:Object) : void
      {
         var expectedSlot:String = this.formatSlot(this.currentSlot);
         if(param1 == null)
         {
            throw new Error("null registration record");
         }
         if(String(param1["protocol"]) != PROTOCOL)
         {
            throw new Error("protocol mismatch");
         }
         if(String(param1["slot"]) != expectedSlot)
         {
            throw new Error("slot mismatch: expected " + expectedSlot);
         }
         if(this.sanitizeText(param1["consumerId"],48).length == 0)
         {
            throw new Error("empty consumerId");
         }
         if(this.sanitizeText(param1["version"],24).length == 0)
         {
            throw new Error("empty version");
         }
         if(this.sanitizeText(param1["marker"],24).length == 0)
         {
            throw new Error("empty marker");
         }
      }

      private function removeCurrentLoaderListeners() : void
      {
         if(this.currentLoader == null)
         {
            return;
         }
         this.currentLoader.contentLoaderInfo.removeEventListener(Event.INIT,this.onConsumerInit);
         this.currentLoader.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onConsumerComplete);
         this.currentLoader.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onConsumerIoError);
         this.currentLoader.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onConsumerSecurityError);
      }

      private function resolveDisplayMode(param1:DisplayObjectContainer) : String
      {
         var ownerUrl:String = this.resolveOwnerUrl(param1).toLowerCase();
         if(ownerUrl.indexOf("hudmenu_lrg") >= 0)
         {
            return "large";
         }
         return "normal";
      }

      private function resolveOwnerUrl(param1:DisplayObjectContainer) : String
      {
         var ownerUrl:String = "owner-url-unavailable";
         if(param1 == null)
         {
            return "owner-null";
         }
         try
         {
            ownerUrl = this.sanitizeText(param1.loaderInfo.url,160);
         }
         catch(ownerUrlError:Error)
         {
         }
         return ownerUrl;
      }

      private function formatSlot(param1:int) : String
      {
         return param1 < 10 ? "slot-0" + param1 : "slot-" + param1;
      }

      private function createDiagnostics() : void
      {
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",18,16777215,false);
         this.diagnostics = new TextField();
         this.diagnostics.name = "CanvasConsumerDiscoveryDiagnostics";
         this.diagnostics.width = 920;
         this.diagnostics.height = 560;
         this.diagnostics.background = true;
         this.diagnostics.backgroundColor = 1052688;
         this.diagnostics.border = true;
         this.diagnostics.borderColor = 65535;
         this.diagnostics.embedFonts = true;
         this.diagnostics.defaultTextFormat = format;
         this.diagnostics.multiline = true;
         this.diagnostics.wordWrap = true;
         this.diagnostics.selectable = false;
         this.diagnostics.mouseEnabled = false;
         addChild(this.diagnostics);
         this.reapplyVanillaPlacements();
      }

      private function appendDiagnostic(param1:String) : void
      {
         var format:TextFormat = null;
         if(this.disposed || this.diagnostics == null)
         {
            return;
         }
         this.diagnosticLines.push(this.sanitizeText(param1,220));
         while(this.diagnosticLines.length > 18)
         {
            this.diagnosticLines.shift();
         }
         this.diagnostics.text = this.diagnosticLines.join("\n");
         format = new TextFormat("$MAIN_Font_Bold",18,16777215,false);
         this.diagnostics.setTextFormat(format);
      }

      private function sanitizeText(param1:Object, param2:int) : String
      {
         var value:String = param1 == null ? "" : String(param1);
         value = value.replace(/[\r\n\t]+/g," ");
         value = value.replace(/\s{2,}/g," ");
         value = value.replace(/^\s+|\s+$/g,"");
         if(value.length > param2)
         {
            value = value.substr(0,param2 - 3) + "...";
         }
         return value;
      }

      private function onRemovedFromStage(param1:Event) : void
      {
         if(param1.target === this)
         {
            this.dispose();
         }
      }
   }
}
