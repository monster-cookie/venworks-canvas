package
{
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.display.Sprite;

   public final class CanvasHtmlTransform
   {
      public static function parse(value:String) : Matrix
      {
         if(value == null || value == "none") return new Matrix();
         // Pixel translations and degree rotations; percentages require a layout basis.
         if(/%|rad|turn/.test(value)) return null;
         return CanvasSvgGeometry.transform(value.replace(/([0-9.])(?:px|deg)\b/g,"$1"));
      }

      public static function isAnchor(value:String) : Boolean
      {
         return ["top-left","top-center","top-right","center-left","center","center-right","bottom-left","bottom-center","bottom-right"].indexOf(value) >= 0;
      }

      public static function apply(box:Object, safe:Rectangle, designScale:Number = 1) : Boolean
      {
         var sprite:Sprite = box.sprite as Sprite;
         var matrix:Matrix = parse(String(box.style["transform"]));
         if(matrix == null) return false;
         if(!isFinite(designScale) || designScale <= 0) designScale = 1;
         var node:CanvasHtmlNode = box.node as CanvasHtmlNode;
         var presentation:Object = node.presentation;
         if(presentation != null)
         {
            matrix.scale(Number(presentation.scale),Number(presentation.scale));
            matrix.rotate(Number(presentation.rotation)*Math.PI/180);
            // data-vw-x and data-vw-y stay in 1920x1080 design pixels. CSS boxes are already in viewport pixels.
            matrix.tx += Number(presentation.x) * designScale;
            matrix.ty += Number(presentation.y) * designScale;
            sprite.alpha *= Number(presentation.opacity);
         }
         matrix.tx += sprite.x; matrix.ty += sprite.y;
         var anchor:String = node.getAttribute("data-vw-anchor");
         if(anchor != null)
         {
            if(!isAnchor(anchor) || box.style["position"] != "absolute") return false;
            var fx:Number = anchor.indexOf("left") >= 0 ? 0 : anchor.indexOf("right") >= 0 ? 1 : 0.5;
            var fy:Number = anchor.indexOf("top") >= 0 ? 0 : anchor.indexOf("bottom") >= 0 ? 1 : 0.5;
            // Author offsets remain in the host's 1920x1080 design coordinate system.
            var w:Number = Number(box.width); var h:Number = Number(box.height);
            var left:Number = Math.min(0,matrix.a*w,matrix.c*h,matrix.a*w+matrix.c*h);
            var top:Number = Math.min(0,matrix.b*w,matrix.d*h,matrix.b*w+matrix.d*h);
            var right:Number = Math.max(0,matrix.a*w,matrix.c*h,matrix.a*w+matrix.c*h);
            var bottom:Number = Math.max(0,matrix.b*w,matrix.d*h,matrix.b*w+matrix.d*h);
            matrix.tx += safe.x + fx*safe.width - left - fx*(right-left);
            matrix.ty += safe.y + fy*safe.height - top - fy*(bottom-top);
         }
         for each(var x:Number in [0,Number(box.width)])
            for each(var y:Number in [0,Number(box.height)])
               if(Math.abs(matrix.a*x+matrix.c*y+matrix.tx) > CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE || Math.abs(matrix.b*x+matrix.d*y+matrix.ty) > CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE) return false;
         sprite.transform.matrix = matrix;
         return true;
      }
   }
}
