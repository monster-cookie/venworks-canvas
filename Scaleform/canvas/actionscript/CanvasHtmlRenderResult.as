package
{
   import flash.display.Sprite;

   public final class CanvasHtmlRenderResult
   {
      public var success:Boolean;

      public var display:Sprite;

      public var width:Number;

      public var height:Number;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasHtmlRenderResult(param1:Boolean, param2:Sprite, param3:Number, param4:Number, param5:CanvasHtmlDiagnostic)
      {
         this.success = param1;
         this.display = param2;
         this.width = param3;
         this.height = param4;
         this.diagnostic = param5;
      }
   }
}
