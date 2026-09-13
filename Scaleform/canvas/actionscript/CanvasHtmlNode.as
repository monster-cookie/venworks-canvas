package
{
   public final class CanvasHtmlNode
   {
      public static const ELEMENT:String = "element";

      public static const TEXT:String = "text";

      public var type:String;

      public var name:String;

      public var text:String;

      public var attributes:Array;

      public var children:Array;

      public var offset:int;

      public var referenceOffset:int;

      public function CanvasHtmlNode(param1:String, param2:int)
      {
         this.type = param1;
         this.offset = param2;
         this.referenceOffset = -1;
         this.attributes = [];
         this.children = [];
      }

      public function getAttribute(param1:String) : String
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in this.attributes)
         {
            if(attribute.name == param1)
            {
               return attribute.value;
            }
         }
         return null;
      }

      public function getAttributeOffset(param1:String) : int
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in this.attributes)
         {
            if(attribute.name == param1)
            {
               return attribute.offset;
            }
         }
         return this.offset;
      }

      public function getAttributeValueOffset(param1:String) : int
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in this.attributes)
         {
            if(attribute.name == param1)
            {
               return attribute.valueOffset;
            }
         }
         return this.offset;
      }
   }
}
