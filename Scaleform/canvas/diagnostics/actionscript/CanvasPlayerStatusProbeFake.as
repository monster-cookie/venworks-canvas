package
{
   internal final class CanvasPlayerStatusProbeFake
   {
      public var provider:Object = null;

      public var payload:Object = null;

      public var throwOnGet:Boolean = false;

      public var failSubscribe:Boolean = false;

      public var getCount:int = 0;

      public var subscribeCount:int = 0;

      public var unsubscribeCount:int = 0;

      public var lastName:String = "";

      public var fromClient:Boolean = false;

      private var callback:Function = null;

      public function GetDataFromClient(name:String, fromClient:Boolean) : Object
      {
         this.getCount++;
         this.lastName = name;
         this.fromClient = fromClient;
         if(this.throwOnGet)
         {
            throw new Error("denied");
         }
         return this.provider;
      }

      public function Subscribe(name:String, callback:Function) : void
      {
         this.subscribeCount++;
         this.lastName = name;
         if(name != "PlayerStatusData")
         {
            throw new Error("unexpected channel " + name);
         }
         if(this.failSubscribe)
         {
            throw new Error("denied");
         }
         this.callback = callback;
         if(this.payload != null)
         {
            callback(this.payload);
         }
      }

      public function Unsubscribe(name:String, callback:Function) : void
      {
         this.unsubscribeCount++;
         this.lastName = name;
         this.callback = null;
      }

      public function pushPayload(payload:Object) : void
      {
         this.payload = payload;
         if(this.callback != null)
         {
            this.callback(payload);
         }
      }
   }
}
