package
{
   public final class CanvasUtf8Result
   {
      public var success:Boolean;

      public var text:String;

      public var errorOffset:int;

      public function CanvasUtf8Result(param1:Boolean, param2:String, param3:int)
      {
         this.success = param1;
         this.text = param2;
         this.errorOffset = param3;
      }
   }
}
