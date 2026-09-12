package
{
   internal final class CanvasSubscriptionsTestContext
   {
      private var active:Object = {};

      public var diagnostics:Array = [];

      public function activate(param1:String, param2:Object, param3:int) : void
      {
         this.active[param1] = {"loader":param2,"generation":param3};
      }

      public function deactivate(param1:String) : void
      {
         delete this.active[param1];
      }

      public function isCurrent(param1:String, param2:Object, param3:int) : Boolean
      {
         var record:Object = this.active[param1];
         return record != null && record.loader === param2 && int(record.generation) == param3;
      }

      public function report(param1:String) : void
      {
         this.diagnostics.push(param1);
      }
   }
}
