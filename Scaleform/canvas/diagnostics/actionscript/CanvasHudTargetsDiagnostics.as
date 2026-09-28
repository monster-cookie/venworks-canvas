package
{
   import flash.display.Sprite;
   import fixtures.POIIcon;
   import flash.display.Shape;
   import flash.events.Event;

   public final class CanvasHudTargetsDiagnostics
   {
      public static function run() : void
      {
         testInventory();
         var root:Sprite = new Sprite();
         var center:Sprite = child(root,"CenterGroup_mc");
         var reticle:Sprite = child(center,"ReticleBase_mc");
         var native:Shape = new Shape(); root.addChild(native); reticle.mask = native;
         reticle.visible = false; reticle.alpha = 0.4;
         var hidden:Boolean = false; var disabled:Boolean = false;
         var manager:CanvasHudTargets = new CanvasHudTargets(root,"player",function(h:Boolean,d:Boolean):void { hidden=h; disabled=d; },null);
         check(manager.validate([{target:"player.crosshair"}]) == null,"known target rejected");
         check(manager.validate([{target:"ship.get-up"}]) != null,"foreign host target accepted");
         check(manager.validate([{target:"player.missing"}]) != null,"missing target accepted");
         manager.apply("one",[{target:"player.crosshair",hidden:true,disabled:false},{target:"canvas.watch",hidden:true,disabled:true}]);
         var suppression:Object = reticle.mask;
         check(suppression != null && suppression !== native,"presentation mask not installed");
         check(!reticle.visible && reticle.alpha == 0.4,"engine visibility was overwritten");
         check(hidden && disabled,"watch disable not forwarded");
         manager.apply("two",[{target:"player.crosshair",hidden:false,disabled:true}]);
         manager.release("one");
         check(reticle.mask === suppression && !hidden && !disabled,"consumer release overwrote another suppression");
         var newNative:Shape = new Shape(); root.addChild(newNative); reticle.mask = newNative;
         root.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(reticle.mask === suppression,"native mask change lost suppression");
         manager.release("two");
         check(reticle.mask === newNative && !reticle.visible,"release did not restore current engine state");
         manager.apply("one",[{target:"player.center",hidden:true,disabled:false}]);
         manager.apply("two",[{target:"player.crosshair",hidden:true,disabled:false}]);
         manager.release("one");
         check(center.mask == null && reticle.mask !== newNative,"group release cleared child request");
         center.removeChild(reticle);
         var replacement:Sprite = child(center,"ReticleBase_mc");
         root.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(reticle.mask === newNative && replacement.mask != null,"timeline replacement was not reconciled");
         replacement.x = 10; replacement.y = 20;
         manager.apply("placement",[{target:"player.crosshair",offsetX:"12",offsetY:"-4"}]);
         check(replacement.x == 22 && replacement.y == 16,"placement offset failed");
         root.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(replacement.x == 22,"placement accumulated each frame");
         replacement.x = 40;
         root.dispatchEvent(new Event(Event.ENTER_FRAME));
         check(replacement.x == 52,"new engine layout was lost");
         manager.release("placement");
         check(replacement.x == 40 && replacement.y == 20,"placement release lost engine position");
         check(manager.validate([{target:"player.crosshair",offsetX:"NaN"}]) != null,"invalid placement accepted");
         manager.dispose();
         check(replacement.mask == null,"dispose left presentation suppressed");
         check(!root.hasEventListener(Event.ENTER_FRAME),"dispose left frame work active");
      }

      private static function testInventory() : void
      {
         var inventory:CanvasHudDynamicTargets = new CanvasHudDynamicTargets();
         var root:Sprite = new Sprite();
         var marker:POIIcon = new POIIcon(); root.addChild(marker);
         check(inventory.scan(root),"complete inventory failed");
         var paths:Array = inventory.paths("POIIcon").concat();
         check(paths.length == 1 && inventory.find(paths[0]) === marker,"marker inventory absent");
         for(var i:int = 0; i < 4096; i++) root.addChild(new Sprite());
         check(!inventory.scan(root) && inventory.failure == "node-limit","oversized inventory accepted");
         check(inventory.paths("POIIcon").length == 1 && inventory.find(paths[0]) === marker,"failed scan published partial inventory");
         while(root.numChildren > 1) root.removeChildAt(root.numChildren-1);
         var nested:Sprite = root;
         for(i = 0; i < 13; i++) nested = child(nested,"level");
         check(!inventory.scan(root) && inventory.failure == "depth-limit","depth truncation reported success");
         check(inventory.find(paths[0]) === marker,"depth failure replaced complete inventory");
         check(!inventory.scan(null) && inventory.failure == "root-unavailable" && inventory.find(paths[0]) == null,"missing root retained stale objects");
         var replacement:Sprite = new Sprite();
         check(inventory.scan(replacement) && inventory.paths("POIIcon").length == 0,"root replacement retained previous inventory");
      }

      private static function child(parent:Sprite,name:String) : Sprite
      {
         var result:Sprite = new Sprite(); result.name=name; parent.addChild(result); return result;
      }
      private static function check(value:Boolean,message:String) : void { if(!value) throw new Error(message); }
   }
}
