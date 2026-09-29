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
      private var inventoryRoot:DisplayObjectContainer;
      public var failure:String;

      public function scan(root:DisplayObjectContainer) : Boolean
      {
         if(root !== this.inventoryRoot)
         {
            this.objects = {}; this.classes = {};
            this.inventoryRoot = root;
         }
         this.failure = null;
         if(root == null) { this.failure = "root-unavailable"; return false; }
         var nextObjects:Object = {};
         var nextClasses:Object = {};
         var pending:Array = [{object:root,depth:0}];
         var visited:int = 0;
         while(pending.length > 0)
         {
            if(++visited > 65536) { this.failure = "node-limit"; return false; }
            var item:Object = pending.pop();
            var object:DisplayObject = item.object as DisplayObject;
            var name:String = getQualifiedClassName(object).split("::").pop();
            if(CanvasHudTargetCatalog.dynamicClass(name))
            {
               if(this.ids[object] == null) this.ids[object] = "@dynamic:"+(++this.nextId);
               var id:String = this.ids[object];
               nextObjects[id] = object;
               if(nextClasses[name] == null) nextClasses[name] = [];
               nextClasses[name].push(id);
            }
            var container:DisplayObjectContainer = object as DisplayObjectContainer;
            if(container != null && container.numChildren > 0)
            {
               if(item.depth >= 32) { this.failure = "depth-limit"; return false; }
               if(visited + pending.length + container.numChildren > 65536) { this.failure = "node-limit"; return false; }
               for(var i:int = 0; i < container.numChildren; i++) pending.push({object:container.getChildAt(i),depth:item.depth+1});
            }
         }
         this.objects = nextObjects; this.classes = nextClasses;
         return true;
      }

      public function paths(name:String) : Array { return this.classes[name] == null ? [] : this.classes[name]; }
      public function find(id:String) : DisplayObject { var object:DisplayObject = this.objects[id] as DisplayObject; return object != null && this.inventoryRoot != null && this.inventoryRoot.contains(object) ? object : null; }
   }
}
