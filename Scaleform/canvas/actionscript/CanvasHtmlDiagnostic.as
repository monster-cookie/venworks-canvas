package
{
   public final class CanvasHtmlDiagnostic
   {
      public var stage:String;

      public var code:String;

      public var resource:String;

      public var offset:int;

      public var limitId:String;

      public function CanvasHtmlDiagnostic(param1:String, param2:String, param3:String, param4:int = -1, param5:String = null)
      {
         this.stage = param1;
         this.code = param2;
         this.resource = param3;
         this.offset = param4;
         this.limitId = param5;
      }

      public function toString() : String
      {
         var value:String = this.stage + "/" + this.code + " | " + this.resource;
         if(this.offset >= 0)
         {
            value += " @" + this.offset;
         }
         if(this.limitId != null)
         {
            value += " | " + this.limitId;
         }
         return value;
      }
   }
}
