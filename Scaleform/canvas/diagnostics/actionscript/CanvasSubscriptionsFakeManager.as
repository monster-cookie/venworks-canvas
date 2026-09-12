package
{
   internal final class CanvasSubscriptionsFakeManager
   {
      public var getCalls:Array = [];

      public var subscribeCalls:Array = [];

      public var unsubscribeCalls:Array = [];

      private var activeCallbacks:Object = {};

      private var replayValues:Object = {};

      private var hasReplay:Object = {};

      private var subscribeFailures:Object = {};

      private var unsubscribeFailures:Object = {};

      private var maximumActive:Object = {};

      public function setReplay(param1:String, param2:Object) : void
      {
         this.replayValues[param1] = param2;
         this.hasReplay[param1] = true;
      }

      public function failSubscribe(param1:String, param2:int) : void
      {
         this.subscribeFailures[param1] = param2;
      }

      public function failUnsubscribe(param1:String, param2:int) : void
      {
         this.unsubscribeFailures[param1] = param2;
      }

      public function GetDataFromClient(param1:String, param2:Boolean) : Object
      {
         this.getCalls.push(param1);
         return {"dataReady":this.hasReplay[param1] === true};
      }

      public function Subscribe(param1:String, param2:Function) : void
      {
         this.subscribeCalls.push({"channel":param1,"callback":param2});
         var callbacks:Array = this.activeCallbacks[param1] as Array;
         if(callbacks == null)
         {
            callbacks = [];
            this.activeCallbacks[param1] = callbacks;
         }
         callbacks.push(param2);
         if(callbacks.length > int(this.maximumActive[param1]))
         {
            this.maximumActive[param1] = callbacks.length;
         }
         if(this.hasReplay[param1] === true)
         {
            param2({"data":this.replayValues[param1]});
         }
         var failures:int = int(this.subscribeFailures[param1]);
         if(failures > 0)
         {
            this.subscribeFailures[param1] = failures - 1;
            throw new Error("FAKE SUBSCRIBE FAILURE " + param1);
         }
      }

      public function Unsubscribe(param1:String, param2:Function) : void
      {
         this.unsubscribeCalls.push({"channel":param1,"callback":param2});
         var failures:int = int(this.unsubscribeFailures[param1]);
         if(failures > 0)
         {
            this.unsubscribeFailures[param1] = failures - 1;
            throw new Error("FAKE UNSUBSCRIBE FAILURE " + param1);
         }
         var callbacks:Array = this.activeCallbacks[param1] as Array;
         if(callbacks == null)
         {
            return;
         }
         var retained:Array = [];
         var index:int = 0;
         while(index < callbacks.length)
         {
            if(callbacks[index] !== param2)
            {
               retained.push(callbacks[index]);
            }
            index++;
         }
         if(retained.length == 0)
         {
            delete this.activeCallbacks[param1];
         }
         else
         {
            this.activeCallbacks[param1] = retained;
         }
      }

      public function emit(param1:String, param2:Object) : void
      {
         var callbacks:Array = this.activeCallbacks[param1] as Array;
         if(callbacks == null)
         {
            return;
         }
         callbacks = callbacks.concat();
         var index:int = 0;
         while(index < callbacks.length)
         {
            callbacks[index]({"data":param2});
            index++;
         }
      }

      public function countGets(param1:String) : int
      {
         return this.countStrings(this.getCalls,param1);
      }

      public function countSubscribes(param1:String) : int
      {
         return this.countRecords(this.subscribeCalls,param1,null,false);
      }

      public function countUnsubscribes(param1:String) : int
      {
         return this.countRecords(this.unsubscribeCalls,param1,null,false);
      }

      public function countUnsubscribesWith(param1:String, param2:Function) : int
      {
         return this.countRecords(this.unsubscribeCalls,param1,param2,true);
      }

      public function firstSubscribedCallback(param1:String) : Function
      {
         var index:int = 0;
         while(index < this.subscribeCalls.length)
         {
            if(this.subscribeCalls[index].channel === param1)
            {
               return this.subscribeCalls[index].callback as Function;
            }
            index++;
         }
         return null;
      }

      public function wasUnsubscribedWith(param1:String, param2:Function) : Boolean
      {
         return this.countUnsubscribesWith(param1,param2) > 0;
      }

      public function activeCallbackCount(param1:String) : int
      {
         var callbacks:Array = this.activeCallbacks[param1] as Array;
         return callbacks == null ? 0 : callbacks.length;
      }

      public function onlyActiveCallback(param1:String) : Function
      {
         var callbacks:Array = this.activeCallbacks[param1] as Array;
         return callbacks != null && callbacks.length == 1 ? callbacks[0] as Function : null;
      }

      public function maximumActiveCallbackCount(param1:String) : int
      {
         return int(this.maximumActive[param1]);
      }

      private function countStrings(param1:Array, param2:String) : int
      {
         var count:int = 0;
         var index:int = 0;
         while(index < param1.length)
         {
            if(param1[index] === param2)
            {
               count++;
            }
            index++;
         }
         return count;
      }

      private function countRecords(param1:Array, param2:String, param3:Function, param4:Boolean) : int
      {
         var count:int = 0;
         var index:int = 0;
         while(index < param1.length)
         {
            if(param1[index].channel === param2 && (!param4 || param1[index].callback === param3))
            {
               count++;
            }
            index++;
         }
         return count;
      }
   }
}
