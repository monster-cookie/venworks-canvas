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
            else
            {
               return false;
            }
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
         return param1 == "M" || param1 == "m" || param1 == "L" || param1 == "l" || param1 == "H" || param1 == "h" || param1 == "V" || param1 == "v" || param1 == "Z" || param1 == "z";
      }
   }
}
