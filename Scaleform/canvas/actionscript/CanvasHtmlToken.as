package
{
   public final class CanvasHtmlToken
   {
      public static const DOCTYPE:String = "doctype";

      public static const START_TAG:String = "start-tag";

      public static const END_TAG:String = "end-tag";

      public static const TEXT:String = "text";

      public static const CHARACTER_REFERENCE:String = "character-reference";

      public var type:String;

      public var name:String;

      public var attributes:Array;

      public var text:String;

      public var offset:int;

      public function CanvasHtmlToken(param1:String, param2:int)
      {
         this.type = param1;
         this.offset = param2;
         this.attributes = [];
      }
   }
}
