package
{
   import flash.display.BitmapData;

   public final class CanvasHtmlResource
   {
      public var path:String;

      public var kind:String;

      public var text:String;

      public var byteLength:int;

      public var document:CanvasHtmlDocument;

      public var bitmapData:BitmapData;

      public function CanvasHtmlResource(param1:String, param2:String, param3:String, param4:int, param5:CanvasHtmlDocument = null, param6:BitmapData = null)
      {
         this.path = param1;
         this.kind = param2;
         this.text = param3;
         this.byteLength = param4;
         this.document = param5;
         this.bitmapData = param6;
      }

      public function dispose() : void
      {
         if(this.bitmapData != null)
         {
            this.bitmapData.dispose();
            this.bitmapData = null;
         }
         this.text = null;
         this.document = null;
      }
   }
}
