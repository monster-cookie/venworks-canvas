package
{
   public final class CanvasHtmlParseResult
   {
      public var success:Boolean;

      public var document:CanvasHtmlDocument;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasHtmlParseResult(param1:Boolean, param2:CanvasHtmlDocument, param3:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.document = param2;
         this.diagnostic = param3;
      }
   }
}
