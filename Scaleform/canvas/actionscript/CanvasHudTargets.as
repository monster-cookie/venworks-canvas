package
{
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.display.Shape;
   import flash.events.Event;

   // A requested target is held invisible. Alpha stays with the engine. 3D clips such as RightMeters ignore a mask, so visible is reapplied every frame and restored on release.
   public final class CanvasHudTargets
   {
      private var owner:DisplayObjectContainer;
      private var hostKind:String;
      private var watchPresentation:Function;
      private var requests:Object = {};
      private var unavailable:Object = {};
      private var active:Object = {};
      private var dynamicTargets:CanvasHudDynamicTargets = new CanvasHudDynamicTargets();
      private var placements:CanvasHudPlacement = new CanvasHudPlacement();
      private var diagnostic:Function;

      public function CanvasHudTargets(owner:DisplayObjectContainer, hostKind:String, watch:Function, diagnostic:Function)
      {
         this.owner = owner; this.hostKind = hostKind; this.watchPresentation = watch; this.diagnostic = diagnostic;
      }

      public function createSymbol(name:String, value:*, width:Number, height:Number) : DisplayObject
      {
         if(this.hostKind != "player" || !CanvasHtmlNativeSymbol.valid(name,value)) throw new Error("Unsupported native symbol");
         if(name == "compass-marker") return CanvasHtmlNativeSymbol.marker(value);
         var host:CanvasHudTargets = this;
         var path:String = name == "vehicle-exit-prompt" ? "RightMeters_mc.HUDVehicle_mc.GetUpButton_mc" : "RightMeters_mc.EquippedWeaponIconHolder_mc";
         if(this.find(path) == null) throw new Error("Native symbol unavailable: "+name);
         return new CanvasHtmlNativeSymbol(function():DisplayObject {
            var display:DisplayObject = host.find(path);
            if(name != "vehicle-exit-prompt" || display == null) return display;
            var button:DisplayObjectContainer = display as DisplayObjectContainer;
            for each(var glyph:String in ["PCButton_mc","ConsoleButton_mc"]) {
               var child:DisplayObject = button.getChildByName(glyph);
               if(child != null && child.visible) return child;
            }
            return null;
         },width,height);
      }

      public function validate(targets:Array) : String
      {
         for each(var request:Object in targets)
         {
            var paths:Array = CanvasHudTargetCatalog.resolve(String(request.target),this.hostKind);
            if(paths == null) return "unsupported HUD target: " + request.target;
            if(request.offsetX != null || request.offsetY != null)
            {
               if(paths.length != 1 || String(paths[0]).charAt(0) == "@") return "target does not support placement: " + request.target;
               for each(var offset:* in [request.offsetX,request.offsetY])
                  if(offset != null && (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(String(offset)) || !isFinite(Number(offset)) || Math.abs(Number(offset)) > 8192)) return "invalid HUD placement: " + request.target;
            }
         }
         return null;
      }

      public function apply(consumer:String, targets:Array) : void
      {
         var error:String = this.validate(targets);
         if(error != null) throw new Error(error);
         this.requests[consumer] = targets;
         this.refresh(null);
      }

      public function release(consumer:String) : void
      {
         delete this.requests[consumer];
         this.refresh(null);
      }

      public function dispose() : void
      {
         this.requests = {};
         this.refresh(null);
         if(this.owner != null) this.owner.removeEventListener(Event.ENTER_FRAME,this.refresh);
         this.owner = null; this.watchPresentation = null; this.diagnostic = null;
      }

      private function refresh(event:Event) : void
      {
         if(this.owner == null) return;
         var desired:Object = {};
         var placementRequests:Object = {};
         var consumers:Array = [];
         for(var consumer:String in this.requests) consumers.push(consumer);
         consumers.sort();
         // Stable first consumer wins a placement conflict; suppression still combines all consumers.
         for each(consumer in consumers)
            for each(var placement:Object in this.requests[consumer])
               if(placement.offsetX != null || placement.offsetY != null)
               {
                  var placementPath:String = CanvasHudTargetCatalog.resolve(String(placement.target),this.hostKind)[0];
                  if(!placementRequests.hasOwnProperty(placementPath)) placementRequests[placementPath] = {x:Number(placement.offsetX),y:Number(placement.offsetY)};
               }
         this.placements.refresh(placementRequests,this.find);
         var hasDynamic:Boolean = false;
         for each(var declared:Array in this.requests)
            for each(var declaration:Object in declared)
               if(declaration.hidden || declaration.disabled)
                  for each(var candidate:String in CanvasHudTargetCatalog.resolve(String(declaration.target),this.hostKind))
                     if(candidate.indexOf("@ship:") == 0) hasDynamic = true;
         if(hasDynamic)
         {
            var complete:Boolean = this.dynamicTargets.scan(this.find("Reticle_mc") as DisplayObjectContainer);
            var failure:String = this.dynamicTargets.failure;
            if(!complete && this.unavailable["@inventory"] != failure && this.diagnostic != null) this.diagnostic("HUD TARGET INVENTORY | "+failure);
            this.unavailable["@inventory"] = failure;
         }
         else this.dynamicTargets.scan(null);
         var watchHidden:Boolean = false;
         var watchDisabled:Boolean = false;
         for each(var targets:Array in this.requests)
            for each(var request:Object in targets)
               if(request.hidden || request.disabled)
                  for each(var path:String in CanvasHudTargetCatalog.resolve(String(request.target),this.hostKind))
                     if(path == "@watch") { watchHidden = true; watchDisabled ||= Boolean(request.disabled); }
                     else if(path.indexOf("@ship:") == 0) {
                        for each(var dynamicPath:String in this.dynamicTargets.paths(path.substr(6))) desired[dynamicPath] = true;
                     }
                     else desired[path] = true;
         if(this.watchPresentation != null) this.watchPresentation(watchHidden,watchDisabled);
         for(var key:String in this.active)
            if(!desired.hasOwnProperty(key)) { this.restore(this.active[key]); delete this.active[key]; }
         var count:int = 0;
         for(key in desired)
         {
            count++;
            var object:DisplayObject = this.find(key);
            var record:Object = this.active[key];
            if(record != null && record.object !== object)
            {
               this.restore(record); delete this.active[key]; record = null;
            }
            if(object == null)
            {
               // Timeline recreation can temporarily remove a target. Retry on the next frame.
               if(!this.unavailable[key] && this.diagnostic != null) this.diagnostic("HUD TARGET UNAVAILABLE | " + key);
               this.unavailable[key] = true;
               continue;
            }
            delete this.unavailable[key];
            if(record == null)
            {
               var mask:Shape = new Shape();
               mask.name = "CanvasHudSuppression";
               this.owner.addChild(mask);
               record = {object:object,mask:mask,nativeMask:object.mask,nativeVisible:object.visible};
               this.active[key] = record;
            }
            else if(object.mask !== record.mask) record.nativeMask = object.mask;
            object.mask = record.mask;
            object.visible = false;
         }
         if(consumers.length > 0) this.owner.addEventListener(Event.ENTER_FRAME,this.refresh,false,-1000,false);
         else this.owner.removeEventListener(Event.ENTER_FRAME,this.refresh);
      }

      private function restore(record:Object) : void
      {
         var object:DisplayObject = record.object as DisplayObject;
         if(object.mask === record.mask) object.mask = record.nativeMask as DisplayObject;
         object.visible = record.nativeVisible === true;
         var mask:Shape = record.mask as Shape;
         if(mask.parent != null) mask.parent.removeChild(mask);
      }

      private function find(path:String) : DisplayObject
      {
         if(path.indexOf("@dynamic:") == 0) return this.dynamicTargets.find(path);
         var current:DisplayObject = this.owner;
         for each(var part:String in path.split("."))
         {
            var container:DisplayObjectContainer = current as DisplayObjectContainer;
            if(container == null) return null;
            var next:DisplayObject = null;
            try { if(part in container) next = container[part] as DisplayObject; } catch(error:*) { }
            current = next == null ? container.getChildByName(part) : next;
            if(current == null) return null;
         }
         return current;
      }
   }
}
