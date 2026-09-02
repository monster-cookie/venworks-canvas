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
   import flash.utils.getDefinitionByName;

   public final class CanvasConsumerDiscoveryHost extends MovieClip
   {
      private static const ENVELOPE_PREFIX:String = "VWC_EVT/1|";

      private static const SNAPSHOT_TYPE:String = "canvas.registry.snapshot";

      private static const DIAGNOSTIC_TYPE:String = "canvas.registry.diagnostic";

      private static const CONSUMER_PROTOCOL:String = "VWCANVAS_CONSUMER/1";

      private static const PROVIDER:String = "CustomAlertsData";

      private var owner:DisplayObjectContainer;

      private var dataManager:Object;

      private var callback:Function;

      private var subscribed:Boolean = false;

      private var disposed:Boolean = false;

      private var displayMode:String = "normal";

      private var ownerLabel:String = "uninitialized";

      private var latestMessageId:int = -1;

      private var loaders:Object = {};

      private var paths:Object = {};

      private var versions:Object = {};

      private var diagnostics:TextField;

      private var diagnosticLines:Array = [];

      public function CanvasConsumerDiscoveryHost()
      {
         super();
         this.callback = this.onCustomAlertsData;
         addEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage,false,0,true);
      }

      public function initialize(param1:DisplayObjectContainer) : void
      {
         if(this.disposed)
         {
            return;
         }
         this.owner = param1;
         this.ownerLabel = this.resolveOwnerUrl(param1);
         this.displayMode = this.ownerLabel.toLowerCase().indexOf("_lrg") >= 0 ? "large" : "normal";
         this.createDiagnostics();
         this.appendDiagnostic("VWCANVAS-9 DYNAMIC REGISTRY");
         this.appendDiagnostic("HOST " + this.resolveHostKind() + " | MODE " + this.displayMode.toUpperCase());
         this.subscribe();
      }

      public function reapplyVanillaPlacements() : void
      {
         if(this.diagnostics != null)
         {
            this.diagnostics.x = 24;
            this.diagnostics.y = 24;
         }
      }

      public function updateVanillaHudModeVisibility(param1:Array) : void
      {
      }

      public function dispose() : void
      {
         var consumerId:String = null;
         var consumerIds:Array = null;
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         removeEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage);
         if(this.subscribed && this.dataManager != null && this.callback != null)
         {
            try
            {
               this.dataManager.Unsubscribe(PROVIDER,this.callback);
            }
            catch(unsubscribeError:Error)
            {
            }
         }
         this.subscribed = false;
         consumerIds = this.getLoaderIds();
         for each(consumerId in consumerIds)
         {
            this.unloadConsumer(consumerId);
         }
         this.loaders = {};
         this.paths = {};
         this.versions = {};
         if(this.diagnostics != null && this.diagnostics.parent === this)
         {
            removeChild(this.diagnostics);
         }
         this.diagnostics = null;
         this.owner = null;
         this.dataManager = null;
         this.callback = null;
      }

      private function subscribe() : void
      {
         try
         {
            this.dataManager = getDefinitionByName("Shared.AS3.Data.BSUIDataManager");
            if(this.dataManager == null)
            {
               throw new Error("BSUIDataManager definition was null");
            }
            this.dataManager.GetDataFromClient(PROVIDER,true);
            this.dataManager.Subscribe(PROVIDER,this.callback);
            this.subscribed = true;
            this.appendDiagnostic("BRIDGE SUBSCRIBED | " + PROVIDER);
         }
         catch(subscriptionError:Error)
         {
            this.appendDiagnostic("BRIDGE ERROR | " + this.sanitizeText(subscriptionError,140));
         }
      }

      private function onCustomAlertsData(param1:Object) : void
      {
         var data:Object = null;
         var alerts:Array = null;
         var alert:Object = null;
         var text:String = null;
         if(this.disposed || param1 == null)
         {
            return;
         }
         data = param1.data == null ? param1 : param1.data;
         if(data == null || data.aAlerts == null)
         {
            return;
         }
         alerts = data.aAlerts as Array;
         if(alerts == null)
         {
            return;
         }
         for each(alert in alerts)
         {
            if(alert == null || alert.sAlertText == null)
            {
               continue;
            }
            text = String(alert.sAlertText);
            if(text.indexOf(ENVELOPE_PREFIX) == 0)
            {
               this.receiveEnvelope(text);
            }
         }
      }

      private function receiveEnvelope(param1:String) : void
      {
         var fields:Array = param1.split("|");
         if(fields.length < 4 || String(fields[0]) != "VWC_EVT/1")
         {
            return;
         }
         if(String(fields[1]) == SNAPSHOT_TYPE)
         {
            this.receiveSnapshot(fields);
         }
         else if(String(fields[1]) == DIAGNOSTIC_TYPE)
         {
            this.appendDiagnostic("REGISTRY " + fields.slice(3).join(" | "));
         }
      }

      private function receiveSnapshot(param1:Array) : void
      {
         var messageId:int = 0;
         var expectedCount:int = 0;
         var records:Array = null;
         var desired:Object = {};
         var recordText:String = null;
         var fields:Array = null;
         var descriptor:Object = null;
         var consumerId:String = null;
         if(param1.length != 6)
         {
            this.appendDiagnostic("SNAPSHOT REJECTED | FIELD COUNT " + param1.length);
            return;
         }
         messageId = int(param1[2]);
         if(messageId <= this.latestMessageId)
         {
            return;
         }
         expectedCount = int(param1[4]);
         records = String(param1[5]).length == 0 ? [] : String(param1[5]).split(";");
         if(records.length != expectedCount)
         {
            this.appendDiagnostic("SNAPSHOT REJECTED | EXPECTED " + expectedCount + " GOT " + records.length);
            return;
         }
         for each(recordText in records)
         {
            fields = recordText.split("~");
            if(fields.length != 5)
            {
               this.appendDiagnostic("DESCRIPTOR REJECTED | FIELD COUNT " + fields.length);
               return;
            }
            descriptor = {
               "consumerId":this.sanitizeText(fields[0],80),
               "displayName":this.sanitizeText(fields[1],80),
               "normalPath":this.sanitizePath(fields[2]),
               "largePath":this.sanitizePath(fields[3]),
               "version":int(fields[4])
            };
            try
            {
               this.validateDescriptor(descriptor);
            }
            catch(descriptorError:Error)
            {
               this.appendDiagnostic("DESCRIPTOR REJECTED | " + this.sanitizeText(descriptorError,100));
               return;
            }
            if(desired[descriptor.consumerId] != null)
            {
               this.appendDiagnostic("DESCRIPTOR REJECTED | DUPLICATE " + descriptor.consumerId);
               return;
            }
            desired[descriptor.consumerId] = descriptor;
         }
         this.latestMessageId = messageId;
         this.appendDiagnostic("SNAPSHOT " + messageId + " | " + this.sanitizeText(param1[3],40) + " | " + expectedCount + " CONSUMER(S)");
         this.reconcile(desired);
      }

      private function validateDescriptor(param1:Object) : void
      {
         if(param1.consumerId.length == 0 || param1.displayName.length == 0 || param1.version < 1)
         {
            throw new Error("incomplete consumer descriptor");
         }
         var prefix:String = "Interface/VenworksCanvas/Consumers/" + param1.consumerId + "/";
         if(param1.normalPath != prefix + "normal.swf" || param1.largePath != prefix + "large.swf")
         {
            throw new Error("consumer path is not namespaced to " + param1.consumerId);
         }
      }

      private function reconcile(param1:Object) : void
      {
         var consumerId:String = null;
         var consumerIds:Array = this.getLoaderIds();
         var descriptor:Object = null;
         var path:String = null;
         for each(consumerId in consumerIds)
         {
            if(param1[consumerId] == null)
            {
               this.appendDiagnostic("REMOVE " + consumerId);
               this.unloadConsumer(consumerId);
            }
         }
         for(consumerId in param1)
         {
            descriptor = param1[consumerId];
            path = this.displayMode == "large" ? descriptor.largePath : descriptor.normalPath;
            if(this.loaders[consumerId] != null && this.paths[consumerId] == path && this.versions[consumerId] == descriptor.version)
            {
               continue;
            }
            if(this.loaders[consumerId] != null)
            {
               this.unloadConsumer(consumerId);
            }
            this.loadConsumer(consumerId,path,descriptor.version);
         }
      }

      private function getLoaderIds() : Array
      {
         var consumerId:String = null;
         var consumerIds:Array = [];
         for(consumerId in this.loaders)
         {
            consumerIds.push(consumerId);
         }
         return consumerIds;
      }

      private function loadConsumer(param1:String, param2:String, param3:int) : void
      {
         var loader:Loader = new Loader();
         loader.name = param1;
         this.loaders[param1] = loader;
         this.paths[param1] = param2;
         this.versions[param1] = param3;
         loader.contentLoaderInfo.addEventListener(Event.INIT,this.onConsumerInit,false,0,true);
         loader.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onConsumerComplete,false,0,true);
         loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onConsumerError,false,0,true);
         loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onConsumerError,false,0,true);
         this.appendDiagnostic("LOAD " + param1 + " | " + this.displayMode.toUpperCase());
         try
         {
            loader.load(new URLRequest(param2));
         }
         catch(loadError:Error)
         {
            this.appendDiagnostic("LOAD ERROR " + param1 + " | " + this.sanitizeText(loadError,100));
            this.unloadConsumer(param1);
         }
      }

      private function onConsumerInit(param1:Event) : void
      {
         var loader:Loader = param1.currentTarget.loader as Loader;
         var bridge:Object = null;
         var record:Object = null;
         if(loader == null || this.loaders[loader.name] !== loader)
         {
            return;
         }
         try
         {
            bridge = loader.content;
            if(bridge == null || !("getCanvasDiscoveryRecord" in bridge))
            {
               throw new Error("missing getCanvasDiscoveryRecord()");
            }
            record = bridge["getCanvasDiscoveryRecord"]();
            if(record == null || record.protocol != CONSUMER_PROTOCOL || record.consumerId != loader.name || int(record.version) != int(this.versions[loader.name]))
            {
               throw new Error("consumer identity did not match its descriptor");
            }
         }
         catch(validationError:Error)
         {
            this.appendDiagnostic("INVALID " + loader.name + " | " + this.sanitizeText(validationError,100));
            this.unloadConsumer(loader.name);
         }
      }

      private function onConsumerComplete(param1:Event) : void
      {
         var loader:Loader = param1.currentTarget.loader as Loader;
         if(loader == null || this.loaders[loader.name] !== loader)
         {
            return;
         }
         this.removeLoaderListeners(loader);
         if(loader.parent !== this)
         {
            addChild(loader);
         }
         this.appendDiagnostic("READY " + loader.name + " | V" + this.versions[loader.name]);
         this.reapplyVanillaPlacements();
      }

      private function onConsumerError(param1:Event) : void
      {
         var loader:Loader = param1.currentTarget.loader as Loader;
         if(loader == null)
         {
            return;
         }
         this.appendDiagnostic("MISSING " + loader.name + " | " + this.sanitizeText(param1,100));
         this.unloadConsumer(loader.name);
      }

      private function unloadConsumer(param1:String) : void
      {
         var loader:Loader = this.loaders[param1] as Loader;
         if(loader == null)
         {
            delete this.loaders[param1];
            delete this.paths[param1];
            delete this.versions[param1];
            return;
         }
         this.removeLoaderListeners(loader);
         if(loader.content != null && "dispose" in loader.content)
         {
            try
            {
               loader.content["dispose"]();
            }
            catch(disposeError:Error)
            {
            }
         }
         if(loader.parent === this)
         {
            removeChild(loader);
         }
         try
         {
            loader.close();
         }
         catch(closeError:Error)
         {
         }
         try
         {
            loader.unload();
         }
         catch(unloadError:Error)
         {
         }
         delete this.loaders[param1];
         delete this.paths[param1];
         delete this.versions[param1];
      }

      private function removeLoaderListeners(param1:Loader) : void
      {
         param1.contentLoaderInfo.removeEventListener(Event.INIT,this.onConsumerInit);
         param1.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onConsumerComplete);
         param1.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onConsumerError);
         param1.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onConsumerError);
      }

      private function createDiagnostics() : void
      {
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",18,16777215,false);
         this.diagnostics = new TextField();
         this.diagnostics.name = "CanvasConsumerDiscoveryDiagnostics";
         this.diagnostics.width = 960;
         this.diagnostics.height = 300;
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
         while(this.diagnosticLines.length > 10)
         {
            this.diagnosticLines.shift();
         }
         this.diagnostics.text = this.diagnosticLines.join("\n");
         format = new TextFormat("$MAIN_Font_Bold",18,16777215,false);
         this.diagnostics.setTextFormat(format);
      }

      private function resolveHostKind() : String
      {
         return this.ownerLabel.toLowerCase().indexOf("spaceship") >= 0 ? "SHIP HUD" : "PLAYER HUD";
      }

      private function resolveOwnerUrl(param1:DisplayObjectContainer) : String
      {
         if(param1 == null)
         {
            return "owner-null";
         }
         try
         {
            return this.sanitizeText(param1.loaderInfo.url,180);
         }
         catch(ownerUrlError:Error)
         {
         }
         return "owner-url-unavailable";
      }

      private function sanitizePath(param1:Object) : String
      {
         return this.sanitizeText(param1,200).replace(/\\/g,"/");
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
