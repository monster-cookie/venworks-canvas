package
{
   public final class CanvasSubscriptions
   {
      private static const MAX_CONSUMERS:int = 32;

      private var dataManager:Object;

      private var currentConsumer:Function;

      private var diagnostic:Function;

      private var memberships:Object = {};

      private var channelMembers:Object = {};

      private var topicMembers:Object = {};

      private var channelCallbacks:Object = {};

      private var channelSubscribed:Object = {};

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

      public function addConsumer(param1:String, param2:Object, param3:Object, param4:int, param5:Array, param6:Array) : void
      {
         if(this.disposed || this.memberships[param1] != null || this.membershipCount >= MAX_CONSUMERS)
         {
            throw new Error("consumer subscription membership unavailable");
         }
         var membership:Object = {
            "consumerId":param1,
            "bridge":param2,
            "loader":param3,
            "generation":param4,
            "channels":param5.concat(),
            "topics":param6.concat(),
            "ready":false
         };
         this.memberships[param1] = membership;
         this.membershipCount++;
         try
         {
            var index:int = 0;
            var name:String = null;
            var recipients:Array = null;
            while(index < param5.length)
            {
               name = String(param5[index]);
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
               index++;
            }
            index = 0;
            while(index < param6.length)
            {
               name = String(param6[index]);
               recipients = this.topicMembers[name] as Array;
               if(recipients == null)
               {
                  recipients = [];
                  this.topicMembers[name] = recipients;
               }
               recipients.push(membership);
               index++;
            }
         }
         catch(subscriptionError:Error)
         {
            this.removeConsumer(param1);
            throw subscriptionError;
         }
      }

      public function markReady(param1:String) : void
      {
         var membership:Object = this.memberships[param1];
         if(!this.isMembershipCurrent(membership))
         {
            return;
         }
         membership.ready = true;
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
         var registered:Array = this.topicMembers[param1] as Array;
         if(registered == null)
         {
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
         // Invalidate dispatch snapshots before invoking any native unsubscribe or child callback.
         delete this.memberships[param1];
         this.membershipCount--;
         var index:int = 0;
         var name:String = null;
         var recipients:Array = null;
         while(index < membership.channels.length)
         {
            name = String(membership.channels[index]);
            recipients = this.removeMembership(this.channelMembers[name] as Array,membership);
            if(recipients.length == 0)
            {
               this.unsubscribeChannel(name);
               delete this.channelMembers[name];
            }
            else
            {
               this.channelMembers[name] = recipients;
            }
            index++;
         }
         index = 0;
         while(index < membership.topics.length)
         {
            name = String(membership.topics[index]);
            recipients = this.removeMembership(this.topicMembers[name] as Array,membership);
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
         membership.ready = false;
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
         this.memberships = {};
         this.channelMembers = {};
         this.topicMembers = {};
         this.channelCallbacks = {};
         this.channelSubscribed = {};
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
         catch(subscriptionError:Error)
         {
            delete this.channelSubscribed[param1];
            delete this.channelCallbacks[param1];
            try
            {
               this.dataManager.Unsubscribe(param1,callback);
            }
            catch(cleanupError:Error)
            {
               this.report("UI DATA CLEANUP ERROR | " + param1);
            }
            throw subscriptionError;
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
            try
            {
               this.dataManager.Unsubscribe(param1,callback);
            }
            catch(unsubscribeError:Error)
            {
               this.report("UI DATA UNSUBSCRIBE ERROR | " + param1);
            }
         }
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
         catch(snapshotError:Error)
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
         catch(callbackError:Error)
         {
            this.report("UI DATA CALLBACK ERROR | " + param1.consumerId + " | " + param2);
         }
      }

      private function deliverEvent(param1:Object, param2:String, param3:String) : void
      {
         if(!this.isMembershipCurrent(param1) || param1.ready !== true)
         {
            return;
         }
         try
         {
            param1.bridge["handleCanvasEvent"](param2,param3);
         }
         catch(callbackError:Error)
         {
            this.report("EVENT CALLBACK ERROR | " + param1.consumerId + " | " + param2);
         }
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
         catch(currentError:Error)
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

      private function report(param1:String) : void
      {
         if(this.diagnostic != null)
         {
            try
            {
               this.diagnostic(param1);
            }
            catch(diagnosticError:Error)
            {
            }
         }
      }
   }
}
