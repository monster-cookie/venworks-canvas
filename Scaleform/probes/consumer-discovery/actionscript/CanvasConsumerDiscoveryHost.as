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
      private static const ENVELOPE_PREFIX:String = "VWC_EVT/1|";

      private static const SNAPSHOT_TYPE:String = "canvas.registry.snapshot";

      private static const DIAGNOSTIC_TYPE:String = "canvas.registry.diagnostic";

      private static const SNAPSHOT_PREFIX:String = ENVELOPE_PREFIX + SNAPSHOT_TYPE + "|";

      private static const DIAGNOSTIC_PREFIX:String = ENVELOPE_PREFIX + DIAGNOSTIC_TYPE + "|";

      private static const CONSUMER_PROTOCOL:String = "VWCANVAS_CONSUMER/1";

      private static const PROVIDER:String = "CustomAlertsData";

      private static const MAX_SNAPSHOT_CHARACTERS:int = 4096;

      private static const MAX_RECORD_CHARACTERS:int = 512;

      private static const MAX_CONSUMER_MOVIE_URL_CHARACTERS:int = 180;

      private var owner:DisplayObjectContainer;

      private var dataManager:Object;

      private var callback:Function;

      private var subscribed:Boolean = false;

      private var disposed:Boolean = false;

      private var displayMode:String = "normal";

      private var ownerLabel:String = "uninitialized";

      private var latestMessageId:int = -1;

      private var pendingGenerationId:int = -1;

      private var pendingReason:String = "";

      private var pendingPageCount:int = 0;

      private var pendingTotalRecordCount:int = 0;

      private var pendingReceivedPageCount:int = 0;

      private var pendingReceivedRecordCount:int = 0;

      private var pendingPages:Object = {};

      private var pendingPageBodies:Object = {};

      private var pendingHasRejectedDescriptor:Boolean = false;

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
         this.appendDiagnostic("VWCANVAS-9 REGISTRATION LOG TEST");
         this.appendDiagnostic("HOST " + this.resolveHostKind() + " | MODE " + this.displayMode.toUpperCase());
         this.appendDiagnostic("WATCH BRIDGE DISABLED");
         this.appendDiagnostic("CHECK PAPYRUS LOGS | CONSUMER MOVIES NOT LOADED");
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
         this.resetPendingGeneration();
         if(this.diagnostics != null && this.diagnostics.parent === this)
         {
            removeChild(this.diagnostics);
         }
         this.diagnostics = null;
         this.owner = null;
         this.dataManager = null;
         this.callback = null;
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
         if(param1.indexOf(SNAPSHOT_PREFIX) == 0)
         {
            this.receiveSnapshot(param1.substr(SNAPSHOT_PREFIX.length));
            return;
         }
         if(param1.indexOf(DIAGNOSTIC_PREFIX) == 0)
         {
            this.receiveDiagnostic(param1.substr(DIAGNOSTIC_PREFIX.length));
         }
      }

      private function receiveDiagnostic(param1:String) : void
      {
         var cursor:int = 0;
         var messageFrame:Object = null;
         var diagnosticFrame:Object = null;
         try
         {
            messageFrame = this.readFrame(param1,cursor,12);
            cursor = int(messageFrame.next);
            diagnosticFrame = this.readFrame(param1,cursor,220);
            cursor = int(diagnosticFrame.next);
            if(cursor != param1.length)
            {
               throw new Error("trailing diagnostic data");
            }
            this.appendDiagnostic("REGISTRY " + this.parseUnsignedInt(String(messageFrame.value),2147483647) + " | " + this.sanitizeText(diagnosticFrame.value,180));
         }
         catch(diagnosticError:Error)
         {
            this.appendDiagnostic("DIAGNOSTIC REJECTED | " + this.sanitizeText(diagnosticError,100));
         }
      }

      private function receiveSnapshot(param1:String) : void
      {
         var cursor:int = 0;
         var generationFrame:Object = null;
         var reasonFrame:Object = null;
         var pageIndexFrame:Object = null;
         var pageCountFrame:Object = null;
         var totalRecordCountFrame:Object = null;
         var pageRecordCountFrame:Object = null;
         var recordFrame:Object = null;
         var generationId:int = -1;
         var pageIndex:int = 0;
         var pageCount:int = 0;
         var totalRecordCount:int = 0;
         var pageRecordCount:int = 0;
         var pageDescriptors:Array = [];
         var descriptor:Object = null;
         var index:int = 0;
         var pageHasRejectedDescriptor:Boolean = false;
         if(param1.length > MAX_SNAPSHOT_CHARACTERS)
         {
            this.appendDiagnostic("SNAPSHOT REJECTED | OVERSIZED " + param1.length);
            return;
         }
         try
         {
            generationFrame = this.readFrame(param1,cursor,12);
            cursor = int(generationFrame.next);
            reasonFrame = this.readFrame(param1,cursor,40);
            cursor = int(reasonFrame.next);
            pageIndexFrame = this.readFrame(param1,cursor,12);
            cursor = int(pageIndexFrame.next);
            pageCountFrame = this.readFrame(param1,cursor,12);
            cursor = int(pageCountFrame.next);
            totalRecordCountFrame = this.readFrame(param1,cursor,12);
            cursor = int(totalRecordCountFrame.next);
            pageRecordCountFrame = this.readFrame(param1,cursor,12);
            cursor = int(pageRecordCountFrame.next);
            generationId = this.parseUnsignedInt(String(generationFrame.value),2147483647);
            pageIndex = this.parseUnsignedInt(String(pageIndexFrame.value),2147483647);
            pageCount = this.parseUnsignedInt(String(pageCountFrame.value),2147483647);
            totalRecordCount = this.parseUnsignedInt(String(totalRecordCountFrame.value),2147483647);
            pageRecordCount = this.parseUnsignedInt(String(pageRecordCountFrame.value),2147483647);
            if(pageCount < 1 || pageIndex >= pageCount || pageRecordCount > totalRecordCount)
            {
               throw new Error("invalid snapshot page metadata");
            }
            if(generationId <= this.latestMessageId)
            {
               return;
            }
            while(index < pageRecordCount)
            {
               recordFrame = this.readFrame(param1,cursor,MAX_RECORD_CHARACTERS);
               cursor = int(recordFrame.next);
               try
               {
                  descriptor = this.parseDescriptor(String(recordFrame.value));
                  pageDescriptors.push(descriptor);
               }
               catch(descriptorError:Error)
               {
                  pageHasRejectedDescriptor = true;
                  this.appendDiagnostic("DESCRIPTOR REJECTED | " + this.sanitizeText(descriptorError,100));
               }
               index++;
            }
            if(cursor != param1.length)
            {
               throw new Error("trailing snapshot page data");
            }

            if(this.pendingGenerationId >= 0 && generationId < this.pendingGenerationId)
            {
               return;
            }
            if(generationId != this.pendingGenerationId)
            {
               this.resetPendingGeneration();
               this.pendingGenerationId = generationId;
               this.pendingReason = String(reasonFrame.value);
               this.pendingPageCount = pageCount;
               this.pendingTotalRecordCount = totalRecordCount;
            }
            if(this.pendingReason != String(reasonFrame.value) || this.pendingPageCount != pageCount || this.pendingTotalRecordCount != totalRecordCount)
            {
               throw new Error("inconsistent snapshot generation metadata");
            }
            if(this.pendingPages.hasOwnProperty(String(pageIndex)))
            {
               if(this.pendingPageBodies[String(pageIndex)] === param1)
               {
                  return;
               }
               throw new Error("conflicting duplicate snapshot page");
            }
            this.pendingPages[String(pageIndex)] = pageDescriptors;
            this.pendingPageBodies[String(pageIndex)] = param1;
            this.pendingHasRejectedDescriptor = this.pendingHasRejectedDescriptor || pageHasRejectedDescriptor;
            this.pendingReceivedPageCount++;
            this.pendingReceivedRecordCount += pageRecordCount;
         }
         catch(snapshotError:Error)
         {
            this.appendDiagnostic("SNAPSHOT REJECTED | " + this.sanitizeText(snapshotError,100));
            if(generationId == this.pendingGenerationId)
            {
               this.resetPendingGeneration();
            }
            return;
         }

         if(this.pendingReceivedPageCount == this.pendingPageCount)
         {
            this.commitPendingGeneration();
         }
      }

      private function commitPendingGeneration() : void
      {
         var pageIndex:int = 0;
         var pageDescriptors:Array = null;
         var descriptor:Object = null;
         var desired:Object = {};
         if(this.pendingGenerationId < 0 || this.pendingReceivedPageCount != this.pendingPageCount || this.pendingReceivedRecordCount != this.pendingTotalRecordCount)
         {
            this.appendDiagnostic("SNAPSHOT REJECTED | INCOMPLETE GENERATION");
            this.resetPendingGeneration();
            return;
         }

         while(pageIndex < this.pendingPageCount)
         {
            if(!this.pendingPages.hasOwnProperty(String(pageIndex)))
            {
               this.appendDiagnostic("SNAPSHOT REJECTED | MISSING PAGE " + pageIndex);
               this.resetPendingGeneration();
               return;
            }
            pageDescriptors = this.pendingPages[String(pageIndex)] as Array;
            for each(descriptor in pageDescriptors)
            {
               if(desired[descriptor.consumerId] != null)
               {
                  this.appendDiagnostic("DESCRIPTOR REJECTED | DUPLICATE " + descriptor.consumerId);
               }
               else
               {
                  desired[descriptor.consumerId] = descriptor;
               }
            }
            pageIndex++;
         }

         this.latestMessageId = this.pendingGenerationId;
         this.appendDiagnostic("SNAPSHOT " + this.pendingGenerationId + " | " + this.sanitizeText(this.pendingReason,40) + " | " + this.pendingTotalRecordCount + " CONSUMER(S) | " + this.pendingPageCount + " PAGE(S)");
         if(this.pendingHasRejectedDescriptor)
         {
            this.appendDiagnostic("REMOVAL HOLD | REJECTED DESCRIPTOR");
         }
         this.reconcile(desired,!this.pendingHasRejectedDescriptor);
         this.resetPendingGeneration();
      }

      private function resetPendingGeneration() : void
      {
         this.pendingGenerationId = -1;
         this.pendingReason = "";
         this.pendingPageCount = 0;
         this.pendingTotalRecordCount = 0;
         this.pendingReceivedPageCount = 0;
         this.pendingReceivedRecordCount = 0;
         this.pendingPages = {};
         this.pendingPageBodies = {};
         this.pendingHasRejectedDescriptor = false;
      }

      private function parseDescriptor(param1:String) : Object
      {
         var cursor:int = 0;
         var consumerIdFrame:Object = this.readFrame(param1,cursor,64);
         cursor = int(consumerIdFrame.next);
         var displayNameFrame:Object = this.readFrame(param1,cursor,80);
         cursor = int(displayNameFrame.next);
         var normalPathFrame:Object = this.readFrame(param1,cursor,MAX_CONSUMER_MOVIE_URL_CHARACTERS);
         cursor = int(normalPathFrame.next);
         var largePathFrame:Object = this.readFrame(param1,cursor,MAX_CONSUMER_MOVIE_URL_CHARACTERS);
         cursor = int(largePathFrame.next);
         var versionFrame:Object = this.readFrame(param1,cursor,4);
         cursor = int(versionFrame.next);
         if(cursor != param1.length)
         {
            throw new Error("trailing descriptor data");
         }
         var descriptor:Object = {
            "consumerId":String(consumerIdFrame.value),
            "displayName":String(displayNameFrame.value),
            "normalPath":String(normalPathFrame.value),
            "largePath":String(largePathFrame.value),
            "version":this.parseUnsignedInt(String(versionFrame.value),9999)
         };
         this.validateDescriptor(descriptor);
         return descriptor;
      }

      private function validateDescriptor(param1:Object) : void
      {
         var consumerId:String = String(param1.consumerId);
         var displayName:String = String(param1.displayName);
         if(!/^[a-z0-9][a-z0-9.-]{1,62}[a-z0-9]$/.test(consumerId) || consumerId.indexOf(".") <= 0 || consumerId.indexOf("..") >= 0)
         {
            throw new Error("invalid consumer ID");
         }
         if(displayName.length == 0 || !/^[\x20-\x7E]+$/.test(displayName) || param1.version < 1)
         {
            throw new Error("invalid consumer metadata");
         }
         var prefix:String = "VenworksCanvas/Consumers/" + consumerId + "/";
         if(param1.normalPath != prefix + "normal.swf" || param1.largePath != prefix + "large.swf")
         {
            throw new Error("consumer path is not namespaced to " + consumerId);
         }
      }

      private function readFrame(param1:String, param2:int, param3:int) : Object
      {
         if(param2 < 0 || param2 >= param1.length)
         {
            throw new Error("missing frame");
         }
         var delimiter:int = param1.indexOf(":",param2);
         if(delimiter < 0 || delimiter == param2 || delimiter - param2 > 6)
         {
            throw new Error("invalid frame length");
         }
         var lengthText:String = param1.substring(param2,delimiter);
         var lengthValue:int = this.parseUnsignedInt(lengthText,param3);
         var valueStart:int = delimiter + 1;
         var valueEnd:int = valueStart + lengthValue;
         if(valueEnd > param1.length)
         {
            throw new Error("truncated frame");
         }
         return {
            "value":param1.substring(valueStart,valueEnd),
            "next":valueEnd
         };
      }

      private function parseUnsignedInt(param1:String, param2:int) : int
      {
         if(param1.length == 0 || !/^[0-9]+$/.test(param1))
         {
            throw new Error("invalid unsigned integer");
         }
         var value:Number = Number(param1);
         if(isNaN(value) || value < 0 || value > param2 || value != Math.floor(value))
         {
            throw new Error("unsigned integer out of range");
         }
         return int(value);
      }

      private function reconcile(param1:Object, param2:Boolean) : void
      {
         var consumerId:String = null;
         var consumerIds:Array = this.getLoaderIds();
         var descriptor:Object = null;
         var path:String = null;
         if(param2)
         {
            for each(consumerId in consumerIds)
            {
               if(param1[consumerId] == null)
               {
                  this.appendDiagnostic("REMOVE " + consumerId);
                  this.unloadConsumer(consumerId);
               }
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
         if(loader == null || this.loaders[loader.name] !== loader)
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
