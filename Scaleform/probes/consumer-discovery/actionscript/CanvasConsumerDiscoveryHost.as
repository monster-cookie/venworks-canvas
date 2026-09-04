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

      private static const UI_LOAD_PREFIX:String = ENVELOPE_PREFIX + "canvas.ui.load|";

      private static const MAX_UI_LOAD_CHARACTERS:int = 512;

      private static const SNAPSHOT_TYPE:String = "canvas.registry.snapshot";

      private static const DIAGNOSTIC_TYPE:String = "canvas.registry.diagnostic";

      private static const SNAPSHOT_PREFIX:String = ENVELOPE_PREFIX + SNAPSHOT_TYPE + "|";

      private static const DIAGNOSTIC_PREFIX:String = ENVELOPE_PREFIX + DIAGNOSTIC_TYPE + "|";

      private static const CONSUMER_PROTOCOL:String = "VWCANVAS_CONSUMER/1";

      private static const PROVIDER:String = "CustomAlertsData";

      private static const MAX_SNAPSHOT_CHARACTERS:int = 4096;

      private static const MAX_RECORD_CHARACTERS:int = 512;

      private static const MAX_CONSUMER_MOVIE_URL_CHARACTERS:int = 180;

      private static const MAX_CALLBACK_DIAGNOSTICS:int = 8;

      private static const MAX_ALERT_DIAGNOSTICS:int = 16;

      private var owner:DisplayObjectContainer;

      private var dataManager:Object;

      private var callback:Function;

      private var receiveNotes:Object = {};

      private var callbackCount:int = 0;

      private var alertDiagnosticCount:int = 0;

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
         if(this.disposed || this.owner != null)
         {
            return;
         }
         this.owner = param1;
         this.ownerLabel = this.resolveOwnerUrl(param1);
         this.displayMode = this.ownerLabel.toLowerCase().indexOf("_lrg") >= 0 ? "large" : "normal";
         this.createDiagnostics();
         this.appendDiagnostic("VWCANVAS-9 EXPLICIT UI LOAD TEST");
         this.appendDiagnostic("HOST " + this.resolveHostKind() + " | MODE " + this.displayMode.toUpperCase());
         if(this.resolveHostKind() == "PLAYER HUD")
         {
            this.subscribe();
         }
         else
         {
            this.appendDiagnostic("SHIP UI TRANSPORT DEFERRED");
         }
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
         this.receiveNotes = {};
         this.callbackCount = 0;
         this.alertDiagnosticCount = 0;
      }

      private function subscribe() : void
      {
         if(this.disposed || this.subscribed)
         {
            return;
         }
         try
         {
            var watch:Object = "BottomLeftGroup_mc" in this.owner ? this.owner["BottomLeftGroup_mc"] : null;
            if(watch == null || !("getCanvasWatchDisabled" in watch) || !("getCanvasWatchSubscriptionsRestored" in watch))
            {
               throw new Error("WATCH PATCH MISSING; verify Host archive deployment");
            }
            if(!watch.getCanvasWatchSubscriptionsRestored())
            {
               throw new Error("WATCH SUBSCRIPTIONS NOT RESTORED");
            }
            this.appendDiagnostic("WATCH SUBSCRIPTIONS RESTORED");
            if(!watch.getCanvasWatchDisabled())
            {
               throw new Error("WATCH PRESENTATION ACTIVE");
            }
            this.appendDiagnostic("WATCH PRESENTATION DISABLED");
            // Use the same class reference as the vanilla Watch, not this auxiliary's application domain.
            this.dataManager = watch.getCanvasWatchDataManager();
            var provider:Object = this.dataManager.GetDataFromClient(PROVIDER,true);
            if(provider == null)
            {
               throw new Error("CustomAlertsData provider unavailable");
            }
            this.appendDiagnostic("PROVIDER " + (provider.dataReady ? "READY" : "WAITING FOR CLIENT"));
            // Get first, then Subscribe: vanilla replays an existing ready provider synchronously.
            // Record ownership before that callback so failure cleanup cannot leave an orphan listener.
            this.subscribed = true;
            this.dataManager.Subscribe(PROVIDER,this.callback);
            this.appendDiagnostic("LOAD BRIDGE SUBSCRIBED | " + PROVIDER);
         }
         catch(subscriptionError:Error)
         {
            if(this.subscribed && this.dataManager != null)
            {
               try { this.dataManager.Unsubscribe(PROVIDER,this.callback); }
               catch(cleanupError:Error) { this.appendDiagnostic("BRIDGE CLEANUP ERROR"); }
            }
            this.subscribed = false;
            this.appendDiagnostic("BRIDGE ERROR | " + this.sanitizeText(subscriptionError,140));
         }
      }

      private function onCustomAlertsData(param1:Object) : void
      {
         var data:Object = null;
         var alerts:Object = null;
         var alert:Object = null;
         var text:String = null;
         if(this.disposed)
         {
            return;
         }
         this.callbackCount++;
         try
         {
            if(param1 == null)
            {
               throw new Error("null event");
            }
            // FromClientDataEvent exposes data through a getter; raw payloads are used by fixtures.
            data = "data" in param1 ? param1.data : param1;
            if(data == null || !("aAlerts" in data) || data.aAlerts == null)
            {
               throw new Error("missing aAlerts");
            }
            alerts = data.aAlerts;
            if(typeof alerts != "object" || !("length" in alerts) || typeof alerts.length != "number")
            {
               throw new Error("alerts are not an indexed collection");
            }
            var count:Number = Number(alerts.length);
            if(!isFinite(count) || count < 0 || count != Math.floor(count) || count > 256)
            {
               throw new Error("invalid alert count");
            }
            this.appendCallbackDiagnostic("PROVIDER CALLBACK #" + this.callbackCount + " | ALERTS " + count);
            // Scaleform-native collections need not be ActionScript Array instances.
            for(var index:int = 0; index < count; index++)
            {
               alert = alerts[index];
               if(alert == null || typeof alert != "object" || !("sAlertText" in alert) || typeof alert.sAlertText != "string")
               {
                  this.appendAlertDiagnostic("INVALID ENTRY");
                  continue;
               }
               text = alert.sAlertText;
               if(text.indexOf(UI_LOAD_PREFIX) == 0)
               {
                  this.appendAlertDiagnostic("UI LOAD",text.length);
                  this.receiveEnvelope(text);
               }
               else if(text.indexOf(ENVELOPE_PREFIX) == 0)
               {
                  this.appendAlertDiagnostic("CANVAS OTHER",text.length);
               }
               else
               {
                  this.appendAlertDiagnostic("OTHER",text.length);
               }
            }
         }
         catch(payloadError:Error)
         {
            this.receiveNote("error","PROVIDER PAYLOAD REJECTED | " + this.sanitizeText(payloadError,100));
         }
      }

      private function receiveNote(key:String, message:String) : void
      {
         if(this.receiveNotes[key] !== true)
         {
            this.receiveNotes[key] = true;
            this.appendDiagnostic(message);
         }
      }

      private function appendCallbackDiagnostic(message:String) : void
      {
         if(this.callbackCount <= MAX_CALLBACK_DIAGNOSTICS)
         {
            this.appendDiagnostic(message);
         }
         else if(this.callbackCount == MAX_CALLBACK_DIAGNOSTICS + 1)
         {
            this.appendDiagnostic("PROVIDER CALLBACK DIAGNOSTICS SUPPRESSED");
         }
      }

      private function appendAlertDiagnostic(classification:String, characterCount:int = -1) : void
      {
         this.alertDiagnosticCount++;
         if(this.alertDiagnosticCount <= MAX_ALERT_DIAGNOSTICS)
         {
            var message:String = "PROVIDER ALERT #" + this.alertDiagnosticCount + " | " + classification;
            if(characterCount >= 0)
            {
               message += " | LENGTH " + characterCount;
            }
            this.appendDiagnostic(message);
         }
         else if(this.alertDiagnosticCount == MAX_ALERT_DIAGNOSTICS + 1)
         {
            this.appendDiagnostic("PROVIDER ALERT DIAGNOSTICS SUPPRESSED");
         }
      }

      private function receiveEnvelope(param1:String) : void
      {
         // Legacy snapshot/diagnostic ingress remains disabled. One request only upserts its own consumer.
         if(param1.indexOf(UI_LOAD_PREFIX) == 0)
         {
            try
            {
               var descriptor:Object = this.parseUiLoad(param1);
               var desired:Object = {};
               desired[descriptor.consumerId] = descriptor;
               this.appendDiagnostic("RX LOAD " + descriptor.consumerId + " | V" + descriptor.version);
               this.reconcile(desired,false);
            }
            catch(loadCommandError:Error)
            {
               this.appendDiagnostic("UI LOAD REJECTED | " + this.sanitizeText(loadCommandError,100));
            }
         }
      }

      private function parseUiLoad(packet:String) : Object
      {
         if(packet.length > MAX_UI_LOAD_CHARACTERS || !/^[\x20-\x7E]+$/.test(packet))
         {
            throw new Error("invalid UI load packet size or characters");
         }
         var cursor:int = UI_LOAD_PREFIX.length;
         var protocol:Object = this.readFrame(packet,cursor,1);
         cursor = int(protocol.next);
         if(protocol.value != "1")
         {
            throw new Error("unsupported UI load protocol");
         }
         var id:Object = this.readFrame(packet,cursor,38);
         cursor = int(id.next);
         var version:Object = this.readFrame(packet,cursor,4);
         cursor = int(version.next);
         var normal:Object = this.readFrame(packet,cursor,MAX_CONSUMER_MOVIE_URL_CHARACTERS);
         cursor = int(normal.next);
         var large:Object = this.readFrame(packet,cursor,MAX_CONSUMER_MOVIE_URL_CHARACTERS);
         cursor = int(large.next);
         if(cursor != packet.length)
         {
            throw new Error("trailing UI load data");
         }
         var descriptor:Object = {
            "consumerId":this.normalizeUuid(String(id.value)),
            "displayName":String(id.value),
            "normalPath":String(normal.value),
            "largePath":String(large.value),
            "version":this.parseUnsignedInt(String(version.value),9999)
         };
         this.validateDescriptor(descriptor);
         return descriptor;
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
            "consumerId":this.normalizeUuid(String(consumerIdFrame.value)),
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
         param1.consumerId = this.normalizeUuid(consumerId);
         if(displayName.length == 0 || !/^[\x20-\x7E]+$/.test(displayName) || param1.version < 1)
         {
            throw new Error("invalid consumer metadata");
         }
         var normal:Array = /^VenworksCanvas\/Consumers\/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])\/normal\.swf$/i.exec(String(param1.normalPath));
         var large:Array = /^VenworksCanvas\/Consumers\/([a-z0-9][a-z0-9.-]{1,62}[a-z0-9])\/large\.swf$/i.exec(String(param1.largePath));
         if(normal == null || large == null || String(normal[0]).length != String(param1.normalPath).length || String(large[0]).length != String(param1.largePath).length || String(normal[1]).indexOf("..") >= 0 || String(normal[1]).toLowerCase() != String(large[1]).toLowerCase())
         {
            throw new Error("consumer paths must share one safe asset namespace");
         }
         var prefix:String = "VenworksCanvas/Consumers/" + String(normal[1]).toLowerCase() + "/";
         param1.normalPath = prefix + "normal.swf";
         param1.largePath = prefix + "large.swf";
      }

      // Canonical value key at every external identity intake. No repair, generation, or display-name coupling.
      private function normalizeUuid(value:String) : String
      {
         if(value == null || value.length > 38)
         {
            throw new Error("invalid UUID");
         }
         if(/^\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}$/i.test(value))
         {
            value = value.substring(1,37);
         }
         else if(value.length == 32 && /^[0-9a-f]{32}$/i.test(value))
         {
            value = value.substr(0,8) + "-" + value.substr(8,4) + "-" + value.substr(12,4) + "-" + value.substr(16,4) + "-" + value.substr(20,12);
         }
         if(value.length != 36 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))
         {
            throw new Error("invalid UUID");
         }
         value = value.toLowerCase();
         if(value == "00000000-0000-0000-0000-000000000000")
         {
            throw new Error("nil UUID");
         }
         return value;
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
         param1 = this.normalizeUuid(param1);
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
            if(record == null || record.protocol != CONSUMER_PROTOCOL || this.normalizeUuid(String(record.consumerId)) != loader.name || int(record.version) != int(this.versions[loader.name]))
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
         param1 = this.normalizeUuid(param1);
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
         while(this.diagnosticLines.length > 16)
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
