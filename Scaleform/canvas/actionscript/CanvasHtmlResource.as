package
{
   public final class CanvasHtmlResource
   {
      public var path:String;

      public var kind:String;

      public var text:String;

      public var byteLength:int;

      public var document:CanvasHtmlDocument;

      public function CanvasHtmlResource(param1:String, param2:String, param3:String, param4:int, param5:CanvasHtmlDocument = null)
      {
         this.path = param1;
         this.kind = param2;
         this.text = param3;
         this.byteLength = param4;
         this.document = param5;
      }

      public function dispose() : void
      {
         this.text = null;
         this.document = null;
      }
   }
}
