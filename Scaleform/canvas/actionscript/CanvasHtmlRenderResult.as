package
{
   import flash.display.Sprite;

   public final class CanvasHtmlRenderResult
   {
      public var targets:Array;

      public var boxes:Array;

      public var success:Boolean;

      public var display:Sprite;

      public var width:Number;

      public var height:Number;

      public var diagnostic:CanvasHtmlDiagnostic;

      public function CanvasHtmlRenderResult(param1:Boolean, param2:Sprite, param3:Number, param4:Number, param5:CanvasHtmlDiagnostic, param6:Array = null, param7:Array = null)
      {
         this.targets = param7 == null ? [] : param7;
         this.boxes = param6;
         this.success = param1;
         this.display = param2;
         this.width = param3;
         this.height = param4;
         this.diagnostic = param5;
      }
   }
}
