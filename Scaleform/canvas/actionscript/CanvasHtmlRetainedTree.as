package
{
   import flash.display.DisplayObject;
   import flash.display.Sprite;
   import flash.display.Shape;
   import flash.text.TextField;
   import flash.utils.Dictionary;

   // Layout uses offscreen candidates. Only commit touches the last valid display.
   public final class CanvasHtmlRetainedTree
   {
      public static function index(boxes:Array) : Object
      {
         var result:Object = {};
         if(boxes != null) for each(var box:Object in boxes) result[box.key] = box;
         return result;
      }

      public static function key(node:CanvasHtmlNode, parent:Object) : String
      {
         var identity:String = node.resource+":"+node.offset+":"+node.type+":"+node.name;
         if(parent == null) return "$"+identity;
         var occurrence:int = parent.occurrences.hasOwnProperty(identity) ? int(parent.occurrences[identity]) : 0;
         parent.occurrences[identity] = occurrence+1;
         return parent.key+"/"+identity+":"+occurrence;
      }

      public static function sameNode(a:CanvasHtmlNode, b:CanvasHtmlNode, deep:Boolean = false) : Boolean
      {
         if(a == null || b == null || a.name != b.name || a.type != b.type || a.text != b.text || !sameBinding(a.bindingValue,b.bindingValue) || a.attributes.length != b.attributes.length) return false;
         for(var i:int = 0; i < a.attributes.length; i++)
         {
            var first:CanvasHtmlAttribute = a.attributes[i] as CanvasHtmlAttribute;
            var second:CanvasHtmlAttribute = b.attributes[i] as CanvasHtmlAttribute;
            if(first.name != second.name || first.value != second.value) return false;
         }
         if(deep)
         {
            if(a.children.length != b.children.length) return false;
            for(i = 0; i < a.children.length; i++) if(!sameNode(a.children[i],b.children[i],true)) return false;
         }
         return true;
      }

      private static function sameBinding(a:*, b:*) : Boolean
      {
         if(a === b) return true;
         // The only structured visual binding is the validated, flat native marker descriptor.
         if(a == null || b == null || typeof a != "object" || typeof b != "object") return false;
         return sameStyle(a,b);
      }

      public static function sameStyle(a:Object, b:Object) : Boolean
      {
         for(var name:String in a) if(a[name] !== b[name]) return false;
         for(name in b) if(!a.hasOwnProperty(name)) return false;
         return true;
      }

      public static function canMeasure(box:Object) : Boolean
      {
         var old:Object = box.previous;
         if(old == null || box.measureWidth != old.measureWidth || !sameStyle(box.style,old.style)) return false;
         var node:CanvasHtmlNode = box.node as CanvasHtmlNode;
         return (node.type == CanvasHtmlNode.TEXT || node.name == "svg" || node.name == "img" || node.name == "vw-symbol") && sameNode(node,old.node,true);
      }

      public static function canDraw(box:Object) : Boolean
      {
         var old:Object = box.previous;
         return old != null && box.width == old.width && box.height == old.height && box.sourceIndex == old.sourceIndex && sameStyle(box.style,old.style) && sameNode(box.node,old.node);
      }

      public static function commit(boxes:Array) : void
      {
         var chosen:Dictionary = new Dictionary();
         for(var i:int = boxes.length - 1; i >= 0; i--)
         {
            var box:Object = boxes[i];
            var old:Object = box.previous;
            var candidate:Sprite = box.sprite as Sprite;
            var retained:Sprite = old == null ? candidate : old.sprite as Sprite;
            var desired:Array = [];
            var own:Array = [];
            var display:DisplayObject;
            var replacements:Dictionary = new Dictionary();
            if(old != null)
            {
               var oldChildren:Dictionary = new Dictionary();
               for each(var child:Object in old.children) oldChildren[child.sprite] = true;
               if(box.measureReused || box.drawReused)
               {
                  for(var j:int = 0; j < retained.numChildren; j++)
                  {
                     display = retained.getChildAt(j);
                     if(oldChildren[display]) continue;
                     if(box.measureReused || box.drawReused && CanvasHtmlNode(box.node).type != CanvasHtmlNode.TEXT && ["svg","img","vw-symbol"].indexOf(CanvasHtmlNode(box.node).name) < 0) own.push(display);
                  }
               }
               if(!box.measureReused && box.textField != null && old.textField != null)
               {
                  var source:TextField = box.textField as TextField;
                  var target:TextField = old.textField as TextField;
                  target.defaultTextFormat = source.defaultTextFormat;
                  target.text = source.text;
                  target.setTextFormat(source.defaultTextFormat);
                  target.width = source.width; target.height = source.height;
                  target.x = source.x; target.y = source.y;
                  replacements[source] = target;
                  box.textField = target;
               }
               if(!box.drawReused && CanvasHtmlNode(box.node).name == "vw-meter" && retained.numChildren == 1 && candidate.numChildren == 1 && retained.getChildAt(0) is Shape && candidate.getChildAt(0) is Shape)
               {
                  var meter:Shape = retained.getChildAt(0) as Shape;
                  meter.graphics.copyFrom(Shape(candidate.getChildAt(0)).graphics);
                  replacements[candidate.getChildAt(0)] = meter;
               }
               if(!box.drawReused) retained.graphics.copyFrom(candidate.graphics);
               retained.transform.matrix = candidate.transform.matrix;
               retained.alpha = candidate.alpha;
               retained.visible = candidate.visible;
               retained.scrollRect = candidate.scrollRect;
            }
            for(j = 0; j < candidate.numChildren; j++)
            {
               display = candidate.getChildAt(j);
               desired.push(chosen[display] != null ? chosen[display] : replacements[display] != null ? replacements[display] : display);
            }
            for each(display in own) desired.push(display);
            // Never detach an unchanged child: doing so restarts native ADDED_TO_STAGE work.
            for(j = retained.numChildren - 1; j >= 0; j--)
               if(desired.indexOf(retained.getChildAt(j)) < 0) retained.removeChildAt(j);
            for(j = 0; j < desired.length; j++)
            {
               display = desired[j];
               if(display.parent !== retained) retained.addChildAt(display,Math.min(j,retained.numChildren));
               else if(retained.getChildIndex(display) != j) retained.setChildIndex(display,j);
            }
            chosen[candidate] = retained;
            box.sprite = retained;
            if(box.measureReused) box.textField = old.textField;
            box.previous = null;
         }
      }
   }
}