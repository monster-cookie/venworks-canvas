package
{
   public final class CanvasCssImportResult
   {
      public var success:Boolean;

      public var source:String;

      public var ruleOffset:int;

      public var imports:Array;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasCssImportResult(param1:Boolean, param2:String, param3:int, param4:Array, param5:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.source = param2;
         this.ruleOffset = param3;
         this.imports = param4 == null ? [] : param4;
         this.diagnostic = param5;
      }
   }
}
