package
{
   import flash.display.Graphics;

   public final class CanvasSvgPathRenderer
   {
      public static function render(param1:CanvasHtmlNode, param2:Graphics, param3:Array, param4:Number, param5:Number, param6:Object, param7:Function) : Boolean
      {
         if(param1 == null || param2 == null || param3 == null || param3.length != 4 || !isFinite(param4) || !isFinite(param5) || param4 <= 0 || param5 <= 0 || param7 == null)
         {
            return false;
         }
         var pathData:String = param1.getAttribute("d");
         if(pathData == null || param7(pathData.length) !== true)
         {
            return false;
         }
         var tokens:Array = tokenize(pathData);
         if(tokens == null)
         {
            return false;
         }
         var fill:Object = resolvePaint(param1.getAttribute("fill"),param6,false);
         var stroke:Object = resolvePaint(param1.getAttribute("stroke"),param6,true);
         if(fill == null || stroke == null)
         {
            return false;
         }
         var fillOpacity:Number = param1.getAttribute("fill-opacity") == null ? 1 : Number(param1.getAttribute("fill-opacity"));
         var strokeOpacity:Number = param1.getAttribute("stroke-opacity") == null ? 1 : Number(param1.getAttribute("stroke-opacity"));
         if(!isFinite(fillOpacity+strokeOpacity) || fillOpacity < 0 || fillOpacity > 1 || strokeOpacity < 0 || strokeOpacity > 1) return false;
         fill = {color:fill.color,alpha:Number(fill.alpha)*fillOpacity};
         stroke = {color:stroke.color,alpha:Number(stroke.alpha)*strokeOpacity};
         var strokeWidth:Number = param1.getAttribute("stroke-width") == null ? 1 : Number(param1.getAttribute("stroke-width"));
         if(!isFinite(strokeWidth) || strokeWidth < 0 || strokeWidth > CanvasHtmlLimits.MAX_SVG_STROKE_WIDTH)
         {
            return false;
         }
         var transformedStroke:Number = strokeWidth * (param4 + param5) * 0.5;
         if(!isFinite(transformedStroke) || transformedStroke > CanvasHtmlLimits.MAX_SVG_STROKE_WIDTH)
         {
            return false;
         }
         if(stroke.alpha > 0 && strokeWidth > 0)
         {
            if(param7(1) !== true)
            {
               return false;
            }
            param2.lineStyle(transformedStroke,uint(stroke.color),Number(stroke.alpha));
         }
         else
         {
            if(param7(1) !== true)
            {
               return false;
            }
            param2.lineStyle();
         }
         if(fill.alpha > 0)
         {
            if(param7(1) !== true)
            {
               return false;
            }
            param2.beginFill(uint(fill.color),Number(fill.alpha));
         }
         var minX:Number = Number(param3[0]);
         var minY:Number = Number(param3[1]);
         var viewWidth:Number = Number(param3[2]);
         var viewHeight:Number = Number(param3[3]);
         if(!isBoundedSource(minX) || !isBoundedSource(minY) || !isBoundedSource(viewWidth) || !isBoundedSource(viewHeight) || viewWidth <= 0 || viewHeight <= 0 || !isBoundedSource(minX + viewWidth) || !isBoundedSource(minY + viewHeight))
         {
            return false;
         }
         var currentX:Number = 0;
         var currentY:Number = 0;
         var startX:Number = 0;
         var startY:Number = 0;
         var command:String = null;
         var index:int = 0;
         var hasMove:Boolean = false;
         var previous:String = "";
         var controlX:Number = 0;
         var controlY:Number = 0;
         while(index < tokens.length)
         {
            if(isCommand(String(tokens[index])))
            {
               command = String(tokens[index]);
               index++;
            }
            if(command == null)
            {
               return false;
            }
            var relative:Boolean = command == command.toLowerCase();
            var upper:String = command.toUpperCase();
            if(upper == "Z")
            {
               if(!hasMove)
               {
                  return false;
               }
               var closeX:Number = transformCoordinate(startX,minX,param4);
               var closeY:Number = transformCoordinate(startY,minY,param5);
               if(!isFinite(closeX) || !isFinite(closeY))
               {
                  return false;
               }
               if(param7(1) !== true)
               {
                  return false;
               }
               param2.lineTo(closeX,closeY);
               currentX = startX;
               currentY = startY;
               command = null;
               previous = "Z";
               continue;
            }
            if(upper == "M" || upper == "L")
            {
               if(index + 1 >= tokens.length || isCommand(String(tokens[index])) || isCommand(String(tokens[index + 1])))
               {
                  return false;
               }
               var nextX:Number = Number(tokens[index]);
               var nextY:Number = Number(tokens[index + 1]);
               index += 2;
               if(!isFinite(nextX) || !isFinite(nextY))
               {
                  return false;
               }
               if(relative)
               {
                  nextX += currentX;
                  nextY += currentY;
               }
               if(!isBoundedSource(nextX) || !isBoundedSource(nextY))
               {
                  return false;
               }
               currentX = nextX;
               currentY = nextY;
               var drawX:Number = transformCoordinate(currentX,minX,param4);
               var drawY:Number = transformCoordinate(currentY,minY,param5);
               if(!isFinite(drawX) || !isFinite(drawY))
               {
                  return false;
               }
               if(upper == "M")
               {
                  if(param7(1) !== true)
                  {
                     return false;
                  }
                  param2.moveTo(drawX,drawY);
                  startX = currentX;
                  startY = currentY;
                  hasMove = true;
                  command = relative ? "l" : "L";
               }
               else
               {
                  if(!hasMove)
                  {
                     return false;
                  }
                  if(param7(1) !== true)
                  {
                     return false;
                  }
                  param2.lineTo(drawX,drawY);
               }
            }
            else if(upper == "H" || upper == "V")
            {
               if(index >= tokens.length || isCommand(String(tokens[index])) || !hasMove)
               {
                  return false;
               }
               var coordinate:Number = Number(tokens[index]);
               index++;
               if(!isFinite(coordinate))
               {
                  return false;
               }
               if(upper == "H")
               {
                  currentX = relative ? currentX + coordinate : coordinate;
               }
               else
               {
                  currentY = relative ? currentY + coordinate : coordinate;
               }
               if(!isBoundedSource(currentX) || !isBoundedSource(currentY))
               {
                  return false;
               }
               var lineX:Number = transformCoordinate(currentX,minX,param4);
               var lineY:Number = transformCoordinate(currentY,minY,param5);
               if(!isFinite(lineX) || !isFinite(lineY))
               {
                  return false;
               }
               if(param7(1) !== true)
               {
                  return false;
               }
               param2.lineTo(lineX,lineY);
            }
            else if(upper == "Q" || upper == "T" || upper == "C" || upper == "S")
            {
               var count:int = upper == "C" ? 6 : (upper == "T" ? 2 : 4);
               if(!hasMove || index + count > tokens.length) return false;
               var points:Array = [];
               for(var p:int = 0; p < count; p++)
               {
                  if(isCommand(String(tokens[index]))) return false;
                  var value:Number = Number(tokens[index++]) + (relative ? (p % 2 == 0 ? currentX : currentY) : 0);
                  if(!isBoundedSource(value)) return false;
                  points.push(value);
               }
               if(upper == "T" || upper == "S")
               {
                  var reflect:Boolean = upper == "T" ? (previous == "Q" || previous == "T") : (previous == "C" || previous == "S");
                  points.unshift(reflect ? 2 * currentX - controlX : currentX,reflect ? 2 * currentY - controlY : currentY);
               }
               var transformed:Array = [];
               for(p = 0; p < points.length; p++)
               {
                  value = transformCoordinate(Number(points[p]),p % 2 == 0 ? minX : minY,p % 2 == 0 ? param4 : param5);
                  if(!isFinite(value)) return false;
                  transformed.push(value);
               }
               if(points.length == 4)
               {
                  if(param7(1) !== true) return false;
                  param2.curveTo(transformed[0],transformed[1],transformed[2],transformed[3]);
               }
               else
               {
                  // Bounded cubic subdivision also works on Scaleform's older Graphics API.
                  if(param7(12) !== true) return false;
                  for(var step:int = 1; step <= 12; step++)
                  {
                     var t:Number = step / 12;
                     var u:Number = 1 - t;
                     var cx:Number = u*u*u*currentX + 3*u*u*t*Number(points[0]) + 3*u*t*t*Number(points[2]) + t*t*t*Number(points[4]);
                     var cy:Number = u*u*u*currentY + 3*u*u*t*Number(points[1]) + 3*u*t*t*Number(points[3]) + t*t*t*Number(points[5]);
                     param2.lineTo(transformCoordinate(cx,minX,param4),transformCoordinate(cy,minY,param5));
                  }
               }
               controlX = Number(points[points.length - 4]);
               controlY = Number(points[points.length - 3]);
               currentX = Number(points[points.length - 2]);
               currentY = Number(points[points.length - 1]);
            }
            else
            {
               return false;
            }
            previous = upper;
         }
         if(fill.alpha > 0)
         {
            if(param7(1) !== true)
            {
               return false;
            }
            param2.endFill();
         }
         return hasMove;
      }

      private static function tokenize(param1:String) : Array
      {
         if(param1 == null || param1.length == 0)
         {
            return null;
         }
         var result:Array = [];
         var index:int = 0;
         while(index < param1.length)
         {
            var code:int = param1.charCodeAt(index);
            if(code == 9 || code == 10 || code == 13 || code == 32 || code == 44)
            {
               index++;
               continue;
            }
            var character:String = param1.charAt(index);
            if(isCommand(character))
            {
               result.push(character);
               index++;
            }
            else
            {
               var start:int = index;
               if(character == "-" || character == "+")
               {
                  index++;
               }
               var digits:int = 0;
               while(index < param1.length && param1.charCodeAt(index) >= 48 && param1.charCodeAt(index) <= 57)
               {
                  digits++;
                  index++;
               }
               if(index < param1.length && param1.charAt(index) == ".")
               {
                  index++;
                  while(index < param1.length && param1.charCodeAt(index) >= 48 && param1.charCodeAt(index) <= 57)
                  {
                     digits++;
                     index++;
                  }
               }
               if(digits == 0)
               {
                  return null;
               }
               if(index < param1.length && (param1.charAt(index) == "e" || param1.charAt(index) == "E"))
               {
                  index++;
                  if(param1.charAt(index) == "+" || param1.charAt(index) == "-") index++;
                  var exponentStart:int = index;
                  while(index < param1.length && param1.charCodeAt(index) >= 48 && param1.charCodeAt(index) <= 57) index++;
                  if(index == exponentStart) return null;
               }
               result.push(param1.substring(start,index));
            }
            if(result.length > CanvasHtmlLimits.MAX_SVG_PATH_TOKENS)
            {
               return null;
            }
         }
         return result;
      }

      private static function resolvePaint(param1:String, param2:Object, param3:Boolean) : Object
      {
         if(param1 == null || param1 == "currentcolor")
         {
            return param1 == null && param3 ? {"color":0,"alpha":0} : param2;
         }
         if(param1 == "none" || param1 == "transparent")
         {
            return {"color":0,"alpha":0};
         }
         return CanvasCssValue.parseColor(param1);
      }

      private static function transformCoordinate(param1:Number, param2:Number, param3:Number) : Number
      {
         if(!isBoundedSource(param1) || !isBoundedSource(param2) || !isFinite(param3))
         {
            return NaN;
         }
         var result:Number = (param1 - param2) * param3;
         return isFinite(result) && Math.abs(result) <= CanvasHtmlLimits.MAX_GRAPHICS_COORDINATE ? result : NaN;
      }

      private static function isBoundedSource(param1:Number) : Boolean
      {
         return isFinite(param1) && Math.abs(param1) <= CanvasHtmlLimits.MAX_SVG_COORDINATE;
      }

      private static function isCommand(param1:String) : Boolean
      {
         return param1 != null && param1.length == 1 && "MmLlHhVvZzQqTtCcSs".indexOf(param1) >= 0;
      }
   }
}
