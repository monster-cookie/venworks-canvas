package
{
   import flash.display.Graphics;

   public final class CanvasHtmlMeter
   {
      public static function options(node:CanvasHtmlNode) : Object
      {
         var minimum:Number = numeric(node,"min",0);
         var maximum:Number = numeric(node,"max",1);
         var segments:Number = numeric(node,"segments",1);
         var gap:Number = numeric(node,"gap",0);
         var direction:String = node.getAttribute("direction");
         var partial:String = node.getAttribute("partial");
         if(direction == null) direction = "right";
         if(partial == null) partial = "true";
         if(!isFinite(minimum+maximum+segments+gap) || maximum <= minimum || segments < 1 || segments > 256 || segments != int(segments) || gap < 0 || gap > 256 || ["right","left","up","down"].indexOf(direction) < 0 || partial != "true" && partial != "false") return null;
         return {minimum:minimum,maximum:maximum,segments:int(segments),gap:gap,direction:direction,partial:partial == "true",legacy:node.getAttribute("min") == null && node.getAttribute("max") == null};
      }

      public static function draw(graphics:Graphics, node:CanvasHtmlNode, x:Number, y:Number, width:Number, height:Number, track:Object, fill:Object) : Boolean
      {
         var settings:Object = options(node);
         if(settings == null || !isFinite(Number(node.bindingValue))) return false;
         var value:Number = Number(node.bindingValue);
         if(settings.legacy && value > 1) value /= 100;
         value = Math.max(0,Math.min(1,(value - settings.minimum)/(settings.maximum - settings.minimum)));
         var vertical:Boolean = settings.direction == "up" || settings.direction == "down";
         var reverse:Boolean = settings.direction == "up" || settings.direction == "left";
         var length:Number = vertical ? height : width;
         var size:Number = (length - settings.gap*(settings.segments-1))/settings.segments;
         if(!isFinite(size) || size <= 0) return false;
         graphics.clear();
         for(var index:int = 0; index < settings.segments; index++)
         {
            var position:Number = (reverse ? settings.segments - 1 - index : index)*(size + settings.gap);
            var amount:Number = Math.max(0,Math.min(1,value*settings.segments-index));
            if(!settings.partial) amount = amount >= 1 ? 1 : 0;
            graphics.beginFill(uint(track.color),Number(track.alpha));
            var trackRect:Array = CanvasStageGuard.rectangle(x+(vertical ? 0 : position),y+(vertical ? position : 0),vertical ? width : size,vertical ? size : height);
            graphics.drawRect(trackRect[0],trackRect[1],trackRect[2],trackRect[3]);
            graphics.endFill();
            if(amount > 0)
            {
               var offset:Number = position + (reverse ? size*(1-amount) : 0);
               graphics.beginFill(uint(fill.color),Number(fill.alpha));
               var fillRect:Array = CanvasStageGuard.rectangle(x+(vertical ? 0 : offset),y+(vertical ? offset : 0),vertical ? width : size*amount,vertical ? size*amount : height);
               graphics.drawRect(fillRect[0],fillRect[1],fillRect[2],fillRect[3]);
               graphics.endFill();
            }
         }
         return true;
      }

      private static function numeric(node:CanvasHtmlNode, name:String, fallback:Number) : Number
      {
         var value:String = node.getAttribute(name);
         if(value == null) return fallback;
         if(!/^[-+]?(?:[0-9]*\.[0-9]+|[0-9]+\.?)$/.test(value)) return NaN;
         var result:Number = Number(value);
         return isFinite(result) && Math.abs(result) <= 1000000 ? result : NaN;
      }
   }
}
