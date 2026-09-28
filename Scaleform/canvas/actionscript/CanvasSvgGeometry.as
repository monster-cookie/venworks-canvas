package
{
   import flash.display.Sprite;
   import flash.display.Shape;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;

   // Shared by inline HTML SVG and bounded external SVG resources. No XML runtime.
   public final class CanvasSvgGeometry
   {
      public static function isElement(name:String) : Boolean
      {
         return ["svg","g","path","rect","circle","ellipse","polygon","polyline"].indexOf(name) >= 0;
      }

      public static function allowsAttribute(name:String, attribute:String) : Boolean
      {
         if(!isElement(name)) return false;
         if(["id","class","fill","stroke","stroke-width","fill-opacity","stroke-opacity","opacity","transform"].indexOf(attribute) >= 0) return true;
         if(name == "svg") return ["viewbox","viewBox","width","height","xmlns","data-vw-visible"].indexOf(attribute) >= 0;
         if(name == "path") return attribute == "d";
         if(name == "rect") return ["x","y","width","height","rx","ry"].indexOf(attribute) >= 0;
         if(name == "circle") return ["cx","cy","r"].indexOf(attribute) >= 0;
         if(name == "ellipse") return ["cx","cy","rx","ry"].indexOf(attribute) >= 0;
         return (name == "polygon" || name == "polyline") && attribute == "points";
      }

      public static function dimension(value:String) : String
      {
         if(value == null) return null;
         var numeric:String = value.substr(-2) == "px" ? value.substring(0,value.length-2) : value;
         if(/^[+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?$/.test(numeric))
         {
            var number:Number = Number(numeric);
            return isFinite(number) && number >= 0 && number <= 8192 ? String(number)+"px" : null;
         }
         return CanvasCssValue.parseLength(value,false,true,false) != null ? value : null;
      }

      public static function render(root:CanvasHtmlNode, viewbox:Array, width:Number, height:Number, cascade:CanvasCssCascade, inherited:Object, ancestors:Array, consume:Function, inline:Boolean = false) : Sprite
      {
         var result:Sprite = new Sprite();
         var scaleX:Number = width / Number(viewbox[2]);
         var scaleY:Number = height / Number(viewbox[3]);
         // Draw in the element's pixel size. A later sprite scale would leave viewBox coordinates, including small negatives, in the graphics command and consoles treat those as off-screen.
         var content:Sprite = drawNode(root,cascade,inherited,ancestors,consume,0,{count:0},scaleX,scaleY,viewbox);
         if(content == null) return null;
         if(inline) content.alpha = 1; // The HTML box already applies root opacity.
         result.addChild(content);
         return bounded(result) ? result : null;
      }

      private static function drawNode(node:CanvasHtmlNode, cascade:CanvasCssCascade, inherited:Object, ancestors:Array, consume:Function, depth:int, budget:Object, scaleX:Number, scaleY:Number, viewbox:Array) : Sprite
      {
         if(depth >= CanvasHtmlLimits.MAX_DOM_DEPTH || ++budget.count > CanvasHtmlLimits.MAX_SVG_ELEMENTS || consume(1) !== true || !isElement(node.name)) return null;
         var style:Object = cascade.computeStyle(node,ancestors,inherited);
         if(style == null) return null;
         if(!/^(?:0(?:\.[0-9]+)?|1(?:\.0+)?)$/.test(String(style["opacity"]))) return null;
         var result:Sprite = new Sprite();
         result.mouseEnabled = false;
         result.mouseChildren = false;
         var matrix:Matrix = transform(node.getAttribute("transform"));
         if(matrix == null) return null;
         result.transform.matrix = toPixels(matrix,scaleX,scaleY);
         result.alpha = Number(style["opacity"]);
         result.visible = style["display"] != "none" && style["visibility"] != "hidden";
         if(node.name == "svg" || node.name == "g")
         {
            for each(var child:CanvasHtmlNode in node.children)
            {
               var display:Sprite = drawNode(child,cascade,style,ancestors.concat([node]),consume,depth + 1,budget,scaleX,scaleY,viewbox);
               if(display == null) return null;
               result.addChild(display);
            }
         }
         else
         {
            var path:String = pathData(node);
            if(path == null) return null;
            var geometry:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.ELEMENT,node.offset);
            geometry.name = "path";
            geometry.attributes.push(new CanvasHtmlAttribute("d",path,0,0));
            for each(var property:String in ["fill","stroke","stroke-width","fill-opacity","stroke-opacity"])
               geometry.attributes.push(new CanvasHtmlAttribute(property,String(style[property]),0,0));
            var shape:Shape = new Shape();
            if(!CanvasSvgPathRenderer.render(geometry,shape.graphics,viewbox,scaleX,scaleY,CanvasCssValue.parseColor(String(style["color"])),consume)) return null;
            result.addChild(shape);
         }
         return bounded(result) ? result : null;
      }

      private static function toPixels(matrix:Matrix, scaleX:Number, scaleY:Number) : Matrix
      {
         if(scaleX == 0 || scaleY == 0) return matrix;
         return new Matrix(matrix.a,matrix.b * scaleY / scaleX,matrix.c * scaleX / scaleY,matrix.d,matrix.tx * scaleX,matrix.ty * scaleY);
      }

      private static function bounded(sprite:Sprite) : Boolean
      {
         var bounds:Rectangle = sprite.getBounds(sprite);
         var matrix:Matrix = sprite.transform.matrix;
         // Check all transformed corners, including reflection and rotation.
         for each(var x:Number in [bounds.left,bounds.right])
            for each(var y:Number in [bounds.top,bounds.bottom])
            {
               var tx:Number = matrix.a*x + matrix.c*y + matrix.tx;
               var ty:Number = matrix.b*x + matrix.d*y + matrix.ty;
               if(!isFinite(tx) || !isFinite(ty) || Math.abs(tx) > CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE || Math.abs(ty) > CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE) return false;
            }
         return true;
      }

      private static function number(node:CanvasHtmlNode, name:String, fallback:Number = 0) : Number
      {
         var value:String = node.getAttribute(name);
         if(value == null) return fallback;
         if(value.substr(-2) == "px") value = value.substring(0,value.length-2);
         if(!/^[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?$/.test(value)) return NaN;
         var result:Number = Number(value);
         return isFinite(result) && Math.abs(result) <= CanvasHtmlLimits.MAX_SVG_COORDINATE ? result : NaN;
      }

      private static function pathData(node:CanvasHtmlNode) : String
      {
         if(node.name == "path") return node.getAttribute("d");
         var x:Number;
         var y:Number;
         var rx:Number;
         var ry:Number;
         if(node.name == "rect")
         {
            x = number(node,"x"); y = number(node,"y");
            var w:Number = number(node,"width",NaN); var h:Number = number(node,"height",NaN);
            rx = number(node,"rx",number(node,"ry")); ry = number(node,"ry",rx);
            if(!isFinite(x+y+w+h+rx+ry) || w < 0 || h < 0 || rx < 0 || ry < 0) return null;
            rx = Math.min(rx,w/2); ry = Math.min(ry,h/2);
            if(rx == 0 || ry == 0) return "M"+x+" "+y+"h"+w+"v"+h+"h"+(-w)+"Z";
            // Cubic quarter ellipses, matching the ellipse primitive below.
            var k:Number = 0.5522847498307936;
            return "M"+(x+rx)+" "+y+"H"+(x+w-rx)+"C"+(x+w-rx+k*rx)+" "+y+" "+(x+w)+" "+(y+ry-k*ry)+" "+(x+w)+" "+(y+ry)+"V"+(y+h-ry)+"C"+(x+w)+" "+(y+h-ry+k*ry)+" "+(x+w-rx+k*rx)+" "+(y+h)+" "+(x+w-rx)+" "+(y+h)+"H"+(x+rx)+"C"+(x+rx-k*rx)+" "+(y+h)+" "+x+" "+(y+h-ry+k*ry)+" "+x+" "+(y+h-ry)+"V"+(y+ry)+"C"+x+" "+(y+ry-k*ry)+" "+(x+rx-k*rx)+" "+y+" "+(x+rx)+" "+y+"Z";
         }
         if(node.name == "circle" || node.name == "ellipse")
         {
            x = number(node,"cx"); y = number(node,"cy");
            rx = number(node,node.name == "circle" ? "r" : "rx",NaN);
            ry = node.name == "circle" ? rx : number(node,"ry",NaN);
            if(!isFinite(x+y+rx+ry) || rx < 0 || ry < 0) return null;
            k = 0.5522847498307936;
            return "M"+(x+rx)+" "+y+"C"+(x+rx)+" "+(y+k*ry)+" "+(x+k*rx)+" "+(y+ry)+" "+x+" "+(y+ry)+"C"+(x-k*rx)+" "+(y+ry)+" "+(x-rx)+" "+(y+k*ry)+" "+(x-rx)+" "+y+"C"+(x-rx)+" "+(y-k*ry)+" "+(x-k*rx)+" "+(y-ry)+" "+x+" "+(y-ry)+"C"+(x+k*rx)+" "+(y-ry)+" "+(x+rx)+" "+(y-k*ry)+" "+(x+rx)+" "+y+"Z";
         }
         var points:Array = numbers(node.getAttribute("points"),CanvasHtmlLimits.MAX_SVG_PATH_TOKENS - 2);
         if(points == null || points.length < 4 || points.length % 2 != 0) return null;
         return "M"+points.join(" ")+(node.name == "polygon" ? "Z" : "");
      }

      private static function numbers(source:String, limit:int) : Array
      {
         if(source == null || source.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS) return null;
         var pattern:RegExp = /[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)(?:[eE][-+]?[0-9]+)?/g;
         var values:Array = [];
         var match:Object;
         var end:int = 0;
         while((match = pattern.exec(source)) != null)
         {
            if(source.substring(end,int(match.index)).replace(/[\s,]/g,"").length != 0 || values.length >= limit) return null;
            var value:Number = Number(match[0]);
            if(!isFinite(value) || Math.abs(value) > CanvasHtmlLimits.MAX_SVG_COORDINATE) return null;
            values.push(value); end = pattern.lastIndex;
         }
         return source.substr(end).replace(/[\s,]/g,"").length == 0 ? values : null;
      }

      public static function transform(source:String) : Matrix
      {
         var result:Matrix = new Matrix();
         if(source == null) return result;
         if(source.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS) return null;
         var pattern:RegExp = /(translate|scale|rotate|matrix)\s*\(([^()]*)\)/g;
         var match:Object;
         var end:int = 0;
         var count:int = 0;
         while((match = pattern.exec(source)) != null)
         {
            if(source.substring(end,int(match.index)).replace(/[\s,]/g,"").length != 0 || ++count > 8) return null;
            var values:Array = numbers(String(match[2]),6);
            if(values == null) return null;
            var next:Matrix = new Matrix();
            var name:String = String(match[1]);
            if(name == "matrix" && values.length == 6) next = new Matrix(values[0],values[1],values[2],values[3],values[4],values[5]);
            else if(name == "translate" && (values.length == 1 || values.length == 2)) next.translate(values[0],values.length == 2 ? values[1] : 0);
            else if(name == "scale" && (values.length == 1 || values.length == 2)) next.scale(values[0],values.length == 2 ? values[1] : values[0]);
            else if(name == "rotate" && (values.length == 1 || values.length == 3))
            {
               if(values.length == 3) next.translate(-values[1],-values[2]);
               next.rotate(Number(values[0])*Math.PI/180);
               if(values.length == 3) next.translate(values[1],values[2]);
            }
            else return null;
            // SVG's list multiplies on the right; Flash concat multiplies on the left.
            next.concat(result); result = next;
            for each(var n:Number in [result.a,result.b,result.c,result.d,result.tx,result.ty])
               if(!isFinite(n) || Math.abs(n) > CanvasHtmlLimits.MAX_SVG_COORDINATE) return null;
            end = pattern.lastIndex;
         }
         return count > 0 && source.substr(end).replace(/[\s,]/g,"").length == 0 ? result : null;
      }
   }
}
