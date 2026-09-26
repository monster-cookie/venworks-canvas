package
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.geom.Rectangle;

   public final class CanvasHtmlPrimitivesDiagnostics
   {
      public static function run() : void
      {
         var svg:String = '<svg viewBox="0 0 100 100"><g transform="translate(10 20) scale(.5)" fill="#ffffff"><rect width="20" height="10"/><circle cx="30" cy="30" r="10"/><ellipse cx="50" cy="50" rx="5" ry="10"/><polygon points="0,0 10,0 10,10"/><polyline points="0,0 10,10"/><path d="M 0 0 Q 10 20 20 0 T 40 0 C 40 10 50 10 50 0 S 60 -10 60 0 Z"/></g></svg>';
         var parser:CanvasSvgTextParser = new CanvasSvgTextParser();
         var root:CanvasHtmlNode = parser.parse(svg,"diagnostic.svg");
         check(root != null,"standard SVG did not parse");
         var cascade:CanvasCssCascade = new CanvasCssCascade([]);
         cascade.beginPass();
         var remaining:int = CanvasHtmlLimits.MAX_SVG_WORK;
         var consume:Function = function(work:int):Boolean { remaining -= work; return remaining >= 0; };
         var display:Sprite = CanvasSvgGeometry.render(root,[0,0,100,100],100,100,cascade,null,[],consume);
         check(display != null && display.numChildren == 1,"standard SVG did not render");
         var bounds:Rectangle = display.getBounds(display);
         check(bounds.left >= 9.9 && bounds.top >= 14.9 && bounds.right <= 41 && bounds.bottom <= 51,"SVG transform order or geometry bounds changed");
         check(parser.parse('<svg viewBox="0 0 1 1"><g><script></script></g></svg>',"invalid.svg") == null,"executable SVG element accepted");
         check(parser.parse('<svg viewBox="0 0 1 1"><rect width="1" height="1"><circle r="1"/></rect></svg>',"invalid.svg") == null,"primitive children accepted");
         root = parser.parse('<svg viewBox="0 0 10 10"><path d="M0 0 C1 2 3"/></svg>',"invalid.svg");
         check(root != null && CanvasSvgGeometry.render(root,[0,0,10,10],10,10,cascade,null,[],consume) == null,"truncated cubic accepted");
         root = parser.parse('<svg viewBox="0 0 10 10"><g transform="scale(8192)"><rect width="10" height="10"/></g></svg>',"invalid.svg");
         check(root != null && CanvasSvgGeometry.render(root,[0,0,10,10],10,10,cascade,null,[],consume) == null,"unbounded transformed geometry accepted");
         root = parser.parse('<svg viewBox="0 0 10 10"><path d="M1e0 1 Q2 4 3 1 T5 1 C6 2 7 2 8 1 S9 0 9 1"/></svg>',"valid.svg");
         check(root != null && CanvasSvgGeometry.render(root,[0,0,10,10],10,10,cascade,null,[],consume) != null,"exponents or smooth curves rejected");
         check(CanvasSvgGeometry.render(root,[0,0,10,10],10,10,cascade,null,[],function(work:int):Boolean { return false; }) == null,"SVG work budget bypassed");
         var meter:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.ELEMENT,0);
         meter.name = "vw-meter";
         meter.bindingValue = 25;
         for each(var pair:Array in [["min","0"],["max","100"],["segments","4"],["gap","2"],["direction","up"]])
            meter.attributes.push(new CanvasHtmlAttribute(pair[0],pair[1],0,0));
         var shape:Shape = new Shape();
         check(CanvasHtmlMeter.draw(shape.graphics,meter,0,0,10,46,{color:0,alpha:0},{color:0xffffff,alpha:1}),"segmented meter rejected");
         check(CanvasHtmlMeter.options(meter).segments == 4,"meter settings lost");
         meter.attributes.push(new CanvasHtmlAttribute("partial","invalid",0,0));
         check(CanvasHtmlMeter.options(meter) == null,"invalid partial mode accepted");
      }

      private static function check(value:Boolean, message:String) : void
      {
         if(!value) throw new Error(message);
      }
   }
}
