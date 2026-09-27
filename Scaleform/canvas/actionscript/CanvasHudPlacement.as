package
{
   import flash.display.DisplayObject;

   // Offsets are owned by a consumer, never by the consumer's native display list.
   public final class CanvasHudPlacement
   {
      private var active:Object = {};

      public function refresh(desired:Object, find:Function) : void
      {
         for(var path:String in this.active)
            if(!desired.hasOwnProperty(path)) { this.restore(this.active[path]); delete this.active[path]; }
         for(path in desired)
         {
            var object:DisplayObject = find(path) as DisplayObject;
            var record:Object = this.active[path];
            if(record != null && record.object !== object)
            {
               this.restore(record); delete this.active[path]; record = null;
            }
            if(object == null) continue;
            if(record == null)
            {
               record = {object:object,nativeX:object.x,nativeY:object.y,lastX:object.x,lastY:object.y};
               this.active[path] = record;
            }
            // Capture a new engine layout instead of repeatedly adding our offset.
            if(object.x != record.lastX) record.nativeX = object.x;
            if(object.y != record.lastY) record.nativeY = object.y;
            object.x = record.lastX = Number(record.nativeX) + Number(desired[path].x);
            object.y = record.lastY = Number(record.nativeY) + Number(desired[path].y);
         }
      }

      private function restore(record:Object) : void
      {
         var object:DisplayObject = record.object as DisplayObject;
         if(object.x == record.lastX) object.x = record.nativeX;
         if(object.y == record.lastY) object.y = record.nativeY;
      }
   }
}
