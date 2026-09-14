package
{
   public final class CanvasHtmlLoadResult
   {
      public var success:Boolean;

      public var cancelled:Boolean;

      public var entryDocument:CanvasHtmlDocument;

      public var resources:Array;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasHtmlLoadResult(param1:Boolean, param2:Boolean, param3:CanvasHtmlDocument, param4:Array, param5:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.cancelled = param2;
         this.entryDocument = param3;
         this.resources = param4 == null ? [] : param4;
         this.diagnostic = param5;
      }
   }
}
