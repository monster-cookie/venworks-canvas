package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.utils.Dictionary;
   import flash.utils.getQualifiedClassName;

   // Only catalog-owned class names are accepted. No author-supplied display paths.
   public final class CanvasHudDynamicTargets
   {
      private var ids:Dictionary = new Dictionary(true);
      private var nextId:uint = 0;
      private var objects:Object = {};
      private var classes:Object = {};

      public function scan(root:DisplayObjectContainer) : Boolean
      {
         this.objects = {}; this.classes = {};
         if(root == null) return true;
         var pending:Array = [{object:root,depth:0}];
         var visited:int = 0;
         while(pending.length > 0)
         {
            if(++visited > 4096) return false;
            var item:Object = pending.pop();
            var object:DisplayObject = item.object as DisplayObject;
            var name:String = getQualifiedClassName(object).split("::").pop();
            if(CanvasHudTargetCatalog.dynamicClass(name))
            {
               if(this.ids[object] == null) this.ids[object] = "@dynamic:"+(++this.nextId);
               var id:String = this.ids[object];
               this.objects[id] = object;
               if(this.classes[name] == null) this.classes[name] = [];
               this.classes[name].push(id);
            }
            var container:DisplayObjectContainer = object as DisplayObjectContainer;
            if(container != null && item.depth < 12)
               for(var i:int = 0; i < container.numChildren; i++) pending.push({object:container.getChildAt(i),depth:item.depth+1});
         }
         return true;
      }

      public function paths(name:String) : Array { return this.classes[name] == null ? [] : this.classes[name]; }
      public function find(id:String) : DisplayObject { return this.objects[id] as DisplayObject; }
   }
}
