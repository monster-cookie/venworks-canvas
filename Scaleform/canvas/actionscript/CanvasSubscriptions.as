package
{
   public final class CanvasSubscriptions
   {
      private static const MAX_CONSUMERS:int = 32;

      private static const MAX_UI_CHANNELS:int = 18;

      private static const MAX_EVENT_TOPICS:int = 16;

      private static const MAX_EVENT_TOPIC_CHARACTERS:int = 96;

      private static const MAX_EVENT_DROP_REPORTS:int = 32;

      private var dataManager:Object;

      private var currentConsumer:Function;

      private var diagnostic:Function;

      private var memberships:Object = {};

      private var channelMembers:Object = {};

      private var topicMembers:Object = {};

      private var eventDropReported:Object = {};

      private var eventDropReportCount:int = 0;

      private var retainedDatagrams:CanvasEventQueue = new CanvasEventQueue();

      private var channelCallbacks:Object = {};

      private var channelSubscribed:Object = {};

      private var channelCleanupCallbacks:Object = {};

      private var channelSnapshots:Object = {};

      private var channelHasSnapshot:Object = {};

      private var disposed:Boolean = false;

      private var membershipCount:int = 0;

      public function CanvasSubscriptions(param1:Object, param2:Function, param3:Function)
      {
         this.dataManager = param1;
         this.currentConsumer = param2;
         this.diagnostic = param3;
      }

      public function addConsumer(param1:String, param2:Object, param3:Object, param4:int, param5:Array, param6:Array, param7:Boolean = false, param8:Array = null) : void
      {
         if(this.disposed || this.dataManager == null || this.memberships[param1] != null || this.membershipCount >= MAX_CONSUMERS)
         {
            throw new Error("consumer subscription membership unavailable");
         }
         var channels:Array = this.preflightList(param5,MAX_UI_CHANNELS,true);
         var eventSubscriptions:Array = param8 == null ? this.legacyEventSubscriptions(param6,param7) : this.preflightEventSubscriptions(param8);
         var datagramMode:Boolean = param8 != null;
         var topics:Array = [];
         var eventPolicies:Object = {};
         var hasQueuedPolicy:Boolean = false;
         var subscription:Object = null;
         for each(subscription in eventSubscriptions)
         {
            topics.push(subscription.topic);
            eventPolicies[subscription.topic] = subscription.startup;
            if(subscription.startup != "drop")
            {
               hasQueuedPolicy = true;
            }
         }
         var index:int = 0;
         var name:String = null;
         while(index < channels.length)
         {
            name = String(channels[index]);
            this.requireCleanupResolved(name);
            index++;
         }
         var membership:Object = {
            "consumerId":param1,
            "bridge":param2,
            "loader":param3,
            "generation":param4,
            "channels":channels,
            "topics":topics,
            "eventPolicies":eventPolicies,
            "datagramMode":datagramMode,
            "eventQueue":hasQueuedPolicy ? new CanvasEventQueue() : null,
            "ready":false
         };
         this.memberships[param1] = membership;
         this.membershipCount++;
         try
         {
            var recipients:Array = null;
            index = 0;
            while(index < channels.length)
            {
               name = String(channels[index]);
               recipients = this.channelMembers[name] as Array;
               if(recipients == null)
               {
                  recipients = [];
                  this.channelMembers[name] = recipients;
               }
               recipients.push(membership);
               if(this.channelCallbacks[name] == null)
               {
                  this.subscribeChannel(name);
               }
               if(!this.isMembershipCurrent(membership))
               {
                  throw new Error("consumer subscription membership changed");
               }
               index++;
            }
            index = 0;
            while(index < topics.length)
            {
               name = String(topics[index]);
               recipients = this.topicMembers[name] as Array;
               if(recipients == null)
               {
                  recipients = [];
                  this.topicMembers[name] = recipients;
               }
               recipients.push(membership);
               if(datagramMode && String(eventPolicies[name]) == "latest")
               {
                  this.seedRetainedDatagrams(membership,name);
               }
               index++;
            }
         }
         catch(subscriptionError:*)
         {
            this.removeConsumerMembership(membership);
            throw subscriptionError;
         }
      }

      public function markReady(param1:String) : void
      {
         var membership:Object = this.memberships[param1];
         if(!this.isMembershipCurrent(membership) || membership.ready === true)
         {
            return;
         }
         membership.ready = true;
         var eventQueue:CanvasEventQueue = membership.eventQueue as CanvasEventQueue;
         var queuedEvents:Array = eventQueue == null ? [] : eventQueue.drain();
         var queuedIndex:int = 0;
         while(queuedEvents != null && queuedIndex < queuedEvents.length && this.isMembershipCurrent(membership))
         {
            var queuedEvent:Object = queuedEvents[queuedIndex];
            this.deliverEvent(membership,String(queuedEvent.topic),String(queuedEvent.body));
            queuedIndex++;
         }
         var channels:Array = membership.channels.concat();
         var index:int = 0;
         var channel:String = null;
         while(index < channels.length && this.isMembershipCurrent(membership))
         {
            channel = String(channels[index]);
            if(this.channelHasSnapshot[channel] === true)
            {
               this.deliverData(membership,channel,this.channelSnapshots[channel]);
            }
            index++;
         }
      }

      public function publishEvent(param1:String, param2:String) : void
      {
         if(this.disposed)
         {
            return;
         }
         // CustomWatchAlert may change ASCII casing in transit. Event topics are
         // identifiers, so canonicalize them before subscription lookup and delivery.
         param1 = param1.toLowerCase();
         var retained:Boolean = this.retainDatagram(param1,param2);
         var registered:Array = this.topicMembers[param1] as Array;
         if(registered == null || registered.length == 0)
         {
            if(!retained)
            {
               this.reportEventDrop("NO_TOPIC_MEMBER",param1,"");
            }
            return;
         }
         var recipients:Array = registered.concat();
         var index:int = 0;
         while(index < recipients.length)
         {
            this.deliverEvent(recipients[index],param1,param2);
            index++;
         }
      }

      public function removeConsumer(param1:String) : void
      {
         var membership:Object = this.memberships[param1];
         if(membership == null)
         {
            delete this.memberships[param1];
            return;
         }
         this.removeConsumerMembership(membership);
      }

      private function removeConsumerMembership(param1:Object) : void
      {
         if(param1 == null)
         {
            return;
         }
         // Invalidate dispatch snapshots before invoking any native unsubscribe or child callback.
         if(this.memberships[param1.consumerId] === param1)
         {
            delete this.memberships[param1.consumerId];
            this.membershipCount--;
         }
         var index:int = 0;
         var name:String = null;
         var recipients:Array = null;
         while(index < param1.channels.length)
         {
            name = String(param1.channels[index]);
            recipients = this.removeMembership(this.channelMembers[name] as Array,param1);
            if(recipients.length == 0)
            {
               delete this.channelMembers[name];
               this.unsubscribeChannel(name);
            }
            else
            {
               this.channelMembers[name] = recipients;
            }
            index++;
         }
         index = 0;
         while(index < param1.topics.length)
         {
            name = String(param1.topics[index]);
            recipients = this.removeMembership(this.topicMembers[name] as Array,param1);
            if(recipients.length == 0)
            {
               delete this.topicMembers[name];
            }
            else
            {
               this.topicMembers[name] = recipients;
            }
            index++;
         }
         var eventQueue:CanvasEventQueue = param1.eventQueue as CanvasEventQueue;
         if(eventQueue != null)
         {
            eventQueue.clear();
         }
         param1.eventQueue = null;
         param1.ready = false;
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         var consumerIds:Array = [];
         var consumerId:String = null;
         for(consumerId in this.memberships)
         {
            consumerIds.push(consumerId);
         }
         var index:int = 0;
         while(index < consumerIds.length)
         {
            this.removeConsumer(String(consumerIds[index]));
            index++;
         }
         var cleanupChannels:Array = [];
         var cleanupChannel:String = null;
         for(cleanupChannel in this.channelCleanupCallbacks)
         {
            cleanupChannels.push(cleanupChannel);
         }
         index = 0;
         while(index < cleanupChannels.length)
         {
            cleanupChannel = String(cleanupChannels[index]);
            this.tryCleanupCallback(cleanupChannel,this.channelCleanupCallbacks[cleanupChannel] as Function,"UI DATA DISPOSE CLEANUP ERROR | ");
            index++;
         }
         this.memberships = {};
         this.channelMembers = {};
         this.topicMembers = {};
         this.eventDropReported = {};
         this.eventDropReportCount = 0;
         if(this.retainedDatagrams != null)
         {
            this.retainedDatagrams.clear();
         }
         this.retainedDatagrams = null;
         this.channelCallbacks = {};
         this.channelSubscribed = {};
         this.channelCleanupCallbacks = {};
         this.channelSnapshots = {};
         this.channelHasSnapshot = {};
         this.membershipCount = 0;
         this.dataManager = null;
         this.currentConsumer = null;
         this.diagnostic = null;
      }

      private function subscribeChannel(param1:String) : void
      {
         var callback:Function = this.makeChannelCallback(param1);
         this.channelCallbacks[param1] = callback;
         var provider:Object = this.dataManager.GetDataFromClient(param1,true);
         if(this.disposed || this.channelCallbacks[param1] !== callback)
         {
            throw new Error("UI data subscription ownership changed: " + param1);
         }
         if(provider == null)
         {
            delete this.channelCallbacks[param1];
            throw new Error("UI data provider unavailable: " + param1);
         }
         // Membership and callback ownership precede Subscribe because a ready provider may replay synchronously.
         this.channelSubscribed[param1] = true;
         try
         {
            this.dataManager.Subscribe(param1,callback);
         }
         catch(subscriptionError:*)
         {
            if(this.channelCallbacks[param1] === callback)
            {
               delete this.channelSubscribed[param1];
               delete this.channelCallbacks[param1];
            }
            this.tryCleanupCallback(param1,callback,"UI DATA CLEANUP ERROR | ");
            throw subscriptionError;
         }
         if(this.disposed || this.channelSubscribed[param1] !== true || this.channelCallbacks[param1] !== callback)
         {
            throw new Error("UI data subscription ownership changed: " + param1);
         }
      }

      private function unsubscribeChannel(param1:String) : void
      {
         var callback:Function = this.channelCallbacks[param1] as Function;
         var subscribed:Boolean = this.channelSubscribed[param1] === true;
         // Retire local ownership before native cleanup so synchronous or delayed callbacks are inert.
         delete this.channelSubscribed[param1];
         delete this.channelCallbacks[param1];
         delete this.channelSnapshots[param1];
         delete this.channelHasSnapshot[param1];
         if(subscribed && callback != null && this.dataManager != null)
         {
            this.tryCleanupCallback(param1,callback,"UI DATA UNSUBSCRIBE ERROR | ");
         }
      }

      private function requireCleanupResolved(param1:String) : void
      {
         var callback:Function = this.channelCleanupCallbacks[param1] as Function;
         if(callback == null)
         {
            delete this.channelCleanupCallbacks[param1];
            return;
         }
         if(this.dataManager == null)
         {
            throw new Error("UI data cleanup unresolved: " + param1);
         }
         try
         {
            this.dataManager.Unsubscribe(param1,callback);
         }
         catch(cleanupError:*)
         {
            this.report("UI DATA CLEANUP RETRY ERROR | " + param1);
            throw new Error("UI data cleanup unresolved: " + param1);
         }
         if(this.disposed || this.channelCleanupCallbacks[param1] !== callback)
         {
            throw new Error("UI data cleanup ownership changed: " + param1);
         }
         delete this.channelCleanupCallbacks[param1];
      }

      private function tryCleanupCallback(param1:String, param2:Function, param3:String) : Boolean
      {
         if(param2 == null || this.dataManager == null)
         {
            return true;
         }
         try
         {
            this.dataManager.Unsubscribe(param1,param2);
         }
         catch(cleanupError:*)
         {
            this.channelCleanupCallbacks[param1] = param2;
            this.report(param3 + param1);
            return false;
         }
         if(this.channelCleanupCallbacks[param1] === param2)
         {
            delete this.channelCleanupCallbacks[param1];
         }
         return true;
      }

      private function makeChannelCallback(param1:String) : Function
      {
         var subscriptions:CanvasSubscriptions = this;
         var callback:Function = null;
         callback = function(param2:Object):void
         {
            subscriptions.onChannelData(param1,callback,param2);
         };
         return callback;
      }

      private function onChannelData(param1:String, param2:Function, param3:Object) : void
      {
         if(this.disposed || this.channelSubscribed[param1] !== true || this.channelCallbacks[param1] !== param2)
         {
            return;
         }
         var snapshot:Object = param3;
         try
         {
            if(param3 != null && "data" in param3)
            {
               snapshot = param3.data;
            }
         }
         catch(snapshotError:*)
         {
            this.report("UI DATA REJECTED | " + param1);
            return;
         }
         if(this.disposed || this.channelSubscribed[param1] !== true || this.channelCallbacks[param1] !== param2)
         {
            return;
         }
         var registered:Array = this.channelMembers[param1] as Array;
         if(registered == null)
         {
            return;
         }
         this.channelSnapshots[param1] = snapshot;
         this.channelHasSnapshot[param1] = true;
         var recipients:Array = registered.concat();
         var index:int = 0;
         var membership:Object = null;
         while(index < recipients.length)
         {
            membership = recipients[index];
            if(this.isMembershipCurrent(membership))
            {
               if(membership.ready === true)
               {
                  this.deliverData(membership,param1,snapshot);
               }
            }
            index++;
         }
      }

      private function deliverData(param1:Object, param2:String, param3:Object) : void
      {
         if(!this.isMembershipCurrent(param1))
         {
            return;
         }
         try
         {
            param1.bridge["handleUIData"](param2,param3);
         }
         catch(callbackError:*)
         {
            this.report("UI DATA CALLBACK ERROR | " + param1.consumerId + " | " + param2);
         }
      }

      private function deliverEvent(param1:Object, param2:String, param3:String) : void
      {
         if(!this.isMembershipCurrent(param1))
         {
            this.reportEventDrop("STALE_MEMBERSHIP",param2,param1 == null ? "" : String(param1.consumerId));
            return;
         }
         var coalesceKey:String = param2;
         if(param1.datagramMode === true)
         {
            try
            {
               var datagram:Object = CanvasDatagramCodec.decode(param3);
               coalesceKey += "|" + String(datagram.messageType) + "|" + int(datagram.schemaVersion) + "|" + String(datagram.encoding);
            }
            catch(datagramError:*)
            {
               this.reportEventDrop("INVALID_DATAGRAM",param2,String(param1.consumerId));
               return;
            }
         }
         if(param1.ready !== true)
         {
            var startupPolicy:String = String(param1.eventPolicies[param2]);
            if(startupPolicy == "fifo" || startupPolicy == "latest")
            {
               this.queueEvent(param1,param2,param3,startupPolicy,coalesceKey);
               return;
            }
            this.reportEventDrop("NOT_READY",param2,String(param1.consumerId));
            return;
         }
         try
         {
            param1.bridge["handleCanvasEvent"](param2,param3);
         }
         catch(callbackError:*)
         {
            this.report("EVENT CALLBACK ERROR | " + param1.consumerId + " | " + param2);
         }
      }

      private function retainDatagram(param1:String, param2:String) : Boolean
      {
         if(this.retainedDatagrams == null)
         {
            return false;
         }
         try
         {
            var datagram:Object = CanvasDatagramCodec.decode(param2);
            var coalesceKey:String = param1 + "|" + String(datagram.messageType) + "|" + int(datagram.schemaVersion) + "|" + String(datagram.encoding);
            if(this.retainedDatagrams.enqueue(param1,param2,"latest",coalesceKey))
            {
               this.reportEventDrop("QUEUE_EVICTED",param1,"");
            }
            return true;
         }
         catch(datagramError:*)
         {
         }
         return false;
      }

      private function seedRetainedDatagrams(param1:Object, param2:String) : void
      {
         if(!this.isMembershipCurrent(param1) || this.retainedDatagrams == null)
         {
            return;
         }
         var retained:Array = this.retainedDatagrams.copyForTopic(param2);
         var index:int = 0;
         while(index < retained.length && this.isMembershipCurrent(param1))
         {
            var event:Object = retained[index];
            this.queueEvent(param1,String(event.topic),String(event.body),"latest",String(event.coalesceKey));
            index++;
         }
      }

      private function queueEvent(param1:Object, param2:String, param3:String, param4:String, param5:String) : void
      {
         if(!this.isMembershipCurrent(param1))
         {
            this.reportEventDrop("STALE_MEMBERSHIP",param2,param1 == null ? "" : String(param1.consumerId));
            return;
         }
         var eventQueue:CanvasEventQueue = param1.eventQueue as CanvasEventQueue;
         if(eventQueue == null)
         {
            this.reportEventDrop("NOT_READY",param2,String(param1.consumerId));
            return;
         }
         if(eventQueue.enqueue(param2,param3,param4,param5))
         {
            this.reportEventDrop("QUEUE_EVICTED",param2,String(param1.consumerId));
         }
      }

      private function reportEventDrop(reason:String, topic:String, consumerId:String) : void
      {
         var key:String = reason + "|" + topic + "|" + consumerId;
         if(this.eventDropReported[key] === true || this.eventDropReportCount >= MAX_EVENT_DROP_REPORTS)
         {
            return;
         }
         this.eventDropReported[key] = true;
         this.eventDropReportCount++;
         this.report("EVENT REJECTED | " + reason + " | " + topic + (consumerId == "" ? "" : " | " + consumerId));
      }

      private function isMembershipCurrent(param1:Object) : Boolean
      {
         if(this.disposed || param1 == null || this.memberships[param1.consumerId] !== param1)
         {
            return false;
         }
         try
         {
            return this.currentConsumer(param1.consumerId,param1.loader,param1.generation) === true;
         }
         catch(currentError:*)
         {
         }
         return false;
      }

      private function removeMembership(param1:Array, param2:Object) : Array
      {
         var retained:Array = [];
         if(param1 == null)
         {
            return retained;
         }
         var index:int = 0;
         while(index < param1.length)
         {
            if(param1[index] !== param2)
            {
               retained.push(param1[index]);
            }
            index++;
         }
         return retained;
      }

      private function preflightList(param1:Array, param2:int, param3:Boolean) : Array
      {
         if(param1 == null || param1.length > param2)
         {
            throw new Error(param3 ? "invalid UI channel request" : "invalid event topic request");
         }
         var result:Array = [];
         var seen:Object = {};
         var index:int = 0;
         var value:String = null;
         while(index < param1.length)
         {
            if(typeof param1[index] != "string")
            {
               throw new Error(param3 ? "invalid UI channel request" : "invalid event topic request");
            }
            value = String(param1[index]);
            if(!param3)
            {
               value = value.toLowerCase();
            }
            if(seen.hasOwnProperty("$" + value) || (param3 && !this.isAllowedUiChannel(value)) || (!param3 && !this.isEventTopicValid(value)))
            {
               throw new Error(param3 ? "invalid UI channel request" : "invalid event topic request");
            }
            seen["$" + value] = true;
            result.push(value);
            index++;
         }
         return result;
      }

      private function legacyEventSubscriptions(param1:Array, param2:Boolean) : Array
      {
         var topics:Array = this.preflightList(param1,MAX_EVENT_TOPICS,false);
         var result:Array = [];
         var startup:String = param2 ? "fifo" : "drop";
         for each(var topic:String in topics)
         {
            result.push({"topic":topic,"startup":startup});
         }
         return result;
      }

      private function preflightEventSubscriptions(param1:Array) : Array
      {
         if(param1 == null || param1.length > MAX_EVENT_TOPICS)
         {
            throw new Error("invalid event subscription request");
         }
         var result:Array = [];
         var seen:Object = {};
         for each(var candidate:Object in param1)
         {
            if(candidate == null || !("topic" in candidate) || !("startup" in candidate) || typeof candidate.topic != "string" || typeof candidate.startup != "string")
            {
               throw new Error("invalid event subscription request");
            }
            var topic:String = String(candidate.topic).toLowerCase();
            var startup:String = String(candidate.startup).toLowerCase();
            if(!this.isEventTopicValid(topic) || seen.hasOwnProperty("$" + topic) || startup != "drop" && startup != "latest" && startup != "fifo")
            {
               throw new Error("invalid event subscription request");
            }
            seen["$" + topic] = true;
            result.push({"topic":topic,"startup":startup});
         }
         return result;
      }

      private function isAllowedUiChannel(param1:String) : Boolean
      {
         return param1 == "LocalEnvironmentData" || param1 == "LocalEnvData_Frequent" || param1 == "PlayerData" || param1 == "PlayerFrequentData" || param1 == "PlayerInventoryData" || param1 == "WeaponData" || param1 == "HudJetpackData" || param1 == "HUDStarbornPowersData" || param1 == "FavoritesData" || param1 == "ControlMapData" || param1 == "EnvironmentEffectsData" || param1 == "PersonalEffectsData" || param1 == "StarmapSystemBodyInfoProvider" || param1 == "HudCompassData" || param1 == "HudCrosshairData" || param1 == "HUDStealthData" || param1 == "HUDVehicleData" || param1 == "HUDOpacityData";
      }

      private function isEventTopicValid(param1:String) : Boolean
      {
         if(param1 == null || param1.length < 3 || param1.length > MAX_EVENT_TOPIC_CHARACTERS || !/^[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?(\.[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?)+$/.test(param1))
         {
            return false;
         }
         return param1.substr(0,7).toLowerCase() != "canvas.";
      }

      private function report(param1:String) : void
      {
         if(this.diagnostic != null)
         {
            try
            {
               this.diagnostic(param1);
            }
            catch(diagnosticError:*)
            {
            }
         }
      }
   }
}
