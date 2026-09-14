package
{
   public final class CanvasHtmlComposeResult
   {
      public var success:Boolean;

      public var root:CanvasHtmlNode;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasHtmlComposeResult(param1:Boolean, param2:CanvasHtmlNode, param3:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.root = param2;
         this.diagnostic = param3;
      }
   }
}
