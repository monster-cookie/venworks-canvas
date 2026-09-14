package
{
   public final class CanvasCssParseResult
   {
      public var success:Boolean;

      public var stylesheet:CanvasCssCascade;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasCssParseResult(param1:Boolean, param2:CanvasCssCascade, param3:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.stylesheet = param2;
         this.diagnostic = param3;
      }
   }
}
