package
{
   internal final class CanvasSubscriptionsTestBridge
   {
      public var dataChannels:Array = [];

      public var eventTopics:Array = [];

      public var order:Array = [];

      public var throwData:Boolean = false;

      public var throwEvent:Boolean = false;

      public var onData:Function;

      public function handleUIData(param1:String, param2:Object) : void
      {
         this.dataChannels.push(param1);
         this.order.push("data:" + param1);
         if(this.onData != null)
         {
            this.onData(param1,param2);
         }
         if(this.throwData)
         {
            throw "SUBSCRIPTIONS PROBE DATA FAILURE";
         }
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         this.eventTopics.push(param1);
         if(this.throwEvent)
         {
            throw new Error("SUBSCRIPTIONS PROBE EVENT FAILURE");
         }
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         this.order.push(param1);
      }
   }
}
