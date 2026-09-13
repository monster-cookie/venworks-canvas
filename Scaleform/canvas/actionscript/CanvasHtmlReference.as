package
{
   public final class CanvasHtmlReference
   {
      public static const INCLUDE:String = "include";

      public static const STYLESHEET:String = "stylesheet";

      public static const IMAGE:String = "image";

      public var kind:String;

      public var path:String;

      public var offset:int;

      public function CanvasHtmlReference(param1:String, param2:String, param3:int)
      {
         this.kind = param1;
         this.path = param2;
         this.offset = param3;
      }
   }
}
