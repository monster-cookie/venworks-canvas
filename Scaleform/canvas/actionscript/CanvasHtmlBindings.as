package
{
   public final class CanvasHtmlBindings
   {
      public static function isAttribute(name:String) : Boolean
      {
         return ["data-vw-x","data-vw-y","data-vw-rotation","data-vw-opacity","data-vw-scale","data-vw-asset"].indexOf(name) >= 0;
      }

      public static function resolve(source:CanvasHtmlNode, output:CanvasHtmlNode, scope:Object) : Boolean
      {
         output.presentation = {x:0,y:0,rotation:0,opacity:1,scale:1};
         for each(var name:String in ["x","y","rotation","opacity","scale"])
         {
            var binding:String = source.getAttribute("data-vw-"+name);
            if(binding == null) continue;
            var value:Object = CanvasHtmlData.resolve(scope,binding);
            if(!value.found) continue;
            if(typeof value.value != "number" || !isFinite(Number(value.value))) return false;
            var number:Number = Number(value.value);
            if(name == "scale" && (number < 0.01 || number > 16)) return false;
            if(name == "opacity" ? number < 0 || number > 1 : Math.abs(number) > (name == "rotation" ? 360 : 8192)) return false;
            output.presentation[name] = number;
         }
         binding = source.getAttribute("data-vw-asset");
         if(binding != null)
         {
            var assets:String = source.getAttribute("data-vw-assets");
            if(source.name != "img" || assets == null) return false;
            value = CanvasHtmlData.resolve(scope,binding);
            if(value.found)
            {
               if(typeof value.value != "string" || assets.split(" ").indexOf(String(value.value)) < 0) return false;
               var attributes:Array = [];
               for each(var attribute:CanvasHtmlAttribute in output.attributes)
                  attributes.push(new CanvasHtmlAttribute(attribute.name,attribute.name == "src" ? String(value.value) : attribute.value,attribute.offset,attribute.valueOffset));
               output.attributes = attributes;
            }
         }
         return true;
      }
   }
}
