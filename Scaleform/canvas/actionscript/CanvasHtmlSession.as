package
{
   import flash.display.DisplayObjectContainer;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.geom.Rectangle;

   public final class CanvasHtmlSession
   {
      private var hostLayout:Object;

      private var hudTargets:CanvasHudTargets;
      private var consumerId:String;

      private var mount:DisplayObjectContainer;

      private var loadResult:CanvasHtmlLoadResult;

      private var stylesheet:CanvasCssCascade;

      private var viewport:Sprite;

      private var viewportMask:Shape;

      private var retainedBoxes:Array;

      private var documentDisplay:Sprite;

      private var data:Object = {};

      private var viewportWidth:Number = 1920;

      private var viewportHeight:Number = 1080;

      private var documentHeight:Number = 0;

      private var scrollOffset:Number = 0;

      private var disposed:Boolean;

      private var eventStates:Object = {};

      private var stateEvents:Object = {};

      private var activeState:String;

      private var stagePainted:Boolean;

      public function CanvasHtmlSession(param1:DisplayObjectContainer, param2:CanvasHtmlLoadResult, param3:CanvasHudTargets = null, param4:String = null, param5:Object = null)
      {
         if(param1 == null || param2 == null || !param2.success)
         {
            throw new Error("Canvas HTML session requires a mount and parsed document");
         }
         this.hostLayout = param5;
         if(this.hostLayout != null)
         {
            this.viewportWidth = Number(this.hostLayout.visibleWidth);
            this.viewportHeight = Number(this.hostLayout.visibleHeight);
         }
         this.hudTargets = param3;
         this.consumerId = param4;
         this.mount = param1;
         this.loadResult = param2;
      }

      public function initialize() : CanvasHtmlDiagnostic
      {
         if(this.disposed)
         {
            return new CanvasHtmlDiagnostic("lifecycle","disposed",null);
         }
         var stateFailure:CanvasHtmlDiagnostic = this.indexEventStates();
         if(stateFailure != null)
         {
            return stateFailure;
         }
         var css:CanvasCssParseResult = new CanvasCssParser().parse(this.loadResult);
         if(!css.success)
         {
            return css.diagnostic;
         }
         this.stylesheet = css.stylesheet;
         return this.rebuild(this.data,this.viewportWidth,this.viewportHeight,this.activeState);
      }

      public function setData(param1:Object) : void
      {
         if(this.disposed)
         {
            return;
         }
         CanvasHtmlData.access = "setdata.snapshot";
         var snapshot:Object = CanvasHtmlData.snapshot(param1);
         CanvasHtmlData.access = "setdata.rebuild";
         try
         {
            var failure:CanvasHtmlDiagnostic = this.rebuild(snapshot,this.viewportWidth,this.viewportHeight,this.activeState);
            if(failure != null)
            {
               throw new Error(failure.toString());
            }
            this.data = snapshot;
         }
         catch(rebuildError:*)
         {
            if(!this.keepLastFrame(rebuildError)) throw rebuildError;
         }
      }

      // The menu gallery resizes and dispatches during ready. A 1069 there used to unload the whole document.
      private function keepLastFrame(rebuildError:*) : Boolean
      {
         if(this.documentDisplay == null) return false;
         var text:String = "";
         try { text = String(rebuildError); } catch(ignored:*) { text = ""; }
         return text.indexOf("#1069") >= 0 || text.indexOf("1069 ") == 0;
      }

      public function setHostLayout(layout:Object) : void
      {
         if(this.disposed || layout == null) return;
         var previous:Object = this.hostLayout;
         this.hostLayout = layout;
         try
         {
            var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,Number(layout.visibleWidth),Number(layout.visibleHeight),this.activeState);
            if(failure != null) throw new Error(failure.toString());
         }
         catch(error:*) { this.hostLayout = previous; throw error; }
         this.viewportWidth = Number(layout.visibleWidth);
         this.viewportHeight = Number(layout.visibleHeight);
      }

      public function setViewport(param1:Number, param2:Number) : void
      {
         if(this.disposed)
         {
            return;
         }
         if(!isFinite(param1) || !isFinite(param2) || param1 < 64 || param2 < 64 || param1 > 8192 || param2 > 8192)
         {
            throw new Error("Canvas HTML viewport must be finite and within 64..8192");
         }
         if(param1 == this.viewportWidth && param2 == this.viewportHeight)
         {
            return;
         }
         try
         {
            var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,param1,param2,this.activeState);
            if(failure != null)
            {
               throw new Error(failure.toString());
            }
         }
         catch(rebuildError:*)
         {
            if(!this.keepLastFrame(rebuildError)) throw rebuildError;
            return;
         }
         this.viewportWidth = param1;
         this.viewportHeight = param2;
      }

      public function scrollBy(param1:Number) : void
      {
         if(this.disposed || this.documentDisplay == null)
         {
            return;
         }
         if(!isFinite(param1) || Math.abs(param1) > 8192)
         {
            throw new Error("Canvas HTML scroll delta must be finite and bounded");
         }
         this.scrollOffset = Math.max(0,Math.min(Math.max(0,this.documentHeight - this.viewportHeight),this.scrollOffset + param1));
         this.documentDisplay.y = -this.scrollOffset;
      }

      public function scrollTo(param1:Number) : void
      {
         if(this.disposed || this.documentDisplay == null)
         {
            return;
         }
         if(!isFinite(param1) || Math.abs(param1) > 8192)
         {
            throw new Error("Canvas HTML scroll position must be finite and bounded");
         }
         this.scrollOffset = Math.max(0,Math.min(Math.max(0,this.documentHeight - this.viewportHeight),param1));
         this.documentDisplay.y = -this.scrollOffset;
      }

      public function getScrollState() : Object
      {
         var maximum:Number = Math.max(0,this.documentHeight - this.viewportHeight);
         return {
            "offset":this.scrollOffset,
            "maximum":maximum,
            "viewportHeight":this.viewportHeight,
            "documentHeight":this.documentHeight,
            "canScroll":!this.disposed && this.documentDisplay != null && maximum > 0
         };
      }

      public function dispatch(param1:String) : void
      {
         if(this.disposed)
         {
            return;
         }
         if(!this.isEventTopic(param1) || !this.eventStates.hasOwnProperty(param1))
         {
            throw new Error("Canvas HTML event is invalid or unmapped");
         }
         var nextState:String = String(this.eventStates[param1]);
         if(nextState == this.activeState)
         {
            return;
         }
         try
         {
            var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,this.viewportWidth,this.viewportHeight,nextState);
            if(failure != null)
            {
               throw new Error(failure.toString());
            }
         }
         catch(rebuildError:*)
         {
            if(!this.keepLastFrame(rebuildError)) throw rebuildError;
            return;
         }
         this.activeState = nextState;
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         this.stagePainted = false;
         if(this.hudTargets != null) this.hudTargets.release(this.consumerId);
         this.hudTargets = null;
         if(this.viewport != null)
         {
            this.viewport.mask = null;
            this.viewport.scrollRect = null;
            while(this.viewport.numChildren > 0)
            {
               this.viewport.removeChildAt(this.viewport.numChildren - 1);
            }
            if(this.viewport.parent === this.mount)
            {
               this.mount.removeChild(this.viewport);
            }
         }
         if(this.viewportMask != null && this.viewportMask.parent != null)
         {
            this.viewportMask.parent.removeChild(this.viewportMask);
         }
         this.retainedBoxes = null;
         this.documentDisplay = null;
         this.viewport = null;
         this.viewportMask = null;
         this.stylesheet = null;
         if(this.loadResult != null)
         {
            var resource:CanvasHtmlResource = null;
            for each(resource in this.loadResult.resources)
            {
               resource.dispose();
            }
         }
         this.loadResult = null;
         this.mount = null;
         this.data = null;
         this.documentHeight = 0;
         this.scrollOffset = 0;
         this.eventStates = {};
         this.stateEvents = {};
         this.activeState = null;
      }

      private function rebuild(param1:Object, param2:Number, param3:Number, param4:String) : CanvasHtmlDiagnostic
      {
         if(this.stylesheet == null)
         {
            return new CanvasHtmlDiagnostic("style","stylesheet-unavailable",this.loadResult.entryDocument.resource);
         }
         var composed:CanvasHtmlComposeResult = new CanvasHtmlComposer().compose(this.loadResult,param1,param4);
         if(!composed.success)
         {
            return composed.diagnostic;
         }
         var rendered:CanvasHtmlRenderResult = new CanvasHtmlRenderer().render(composed.root,this.stylesheet,this.loadResult,param2,param3,param2 == this.viewportWidth && param3 == this.viewportHeight ? this.retainedBoxes : null,this.hostLayout,this.hudTargets);
         if(!rendered.success)
         {
            return rendered.diagnostic;
         }
         if(rendered.targets.length > 0)
         {
            var targetError:String = this.hudTargets == null ? "HUD targets unavailable in this host" : this.hudTargets.validate(rendered.targets);
            if(targetError != null) return new CanvasHtmlDiagnostic("render","hud-target-unavailable",this.loadResult.entryDocument.resource,-1,targetError);
         }
         if(!CanvasHtmlRetainedTree.commit(rendered.boxes))
         {
            return new CanvasHtmlDiagnostic("render","attach-failed",this.loadResult.entryDocument.resource,-1,"display-list");
         }
         rendered.display = rendered.boxes[0].sprite as Sprite;
         this.retainedBoxes = rendered.boxes;
         if(this.viewport == null)
         {
            this.viewport = new Sprite();
            this.viewport.name = "CanvasHtmlViewport";
            this.viewport.mouseEnabled = false;
            this.viewport.mouseChildren = false;
         }
         var previousDisplay:Sprite = this.documentDisplay;
         this.documentDisplay = rendered.display;
         this.documentDisplay.name = "CanvasHtmlDocument";
         var attached:Boolean = false;
         try
         {
            if(this.documentDisplay.parent !== this.viewport) this.viewport.addChild(this.documentDisplay);
            attached = true;
         }
         catch(attachError:*) { CanvasHtmlData.access = "render.attach"; }
         if(!attached)
         {
            this.documentDisplay = previousDisplay;
            return new CanvasHtmlDiagnostic("render","attach-failed",this.loadResult.entryDocument.resource,-1,"document");
         }
         if(previousDisplay != null && previousDisplay !== this.documentDisplay && previousDisplay.parent === this.viewport)
         {
            this.viewport.removeChild(previousDisplay);
         }
         this.viewport.x = this.hostLayout == null ? 0 : Number(this.hostLayout.visibleX);
         this.viewport.y = this.hostLayout == null ? 0 : Number(this.hostLayout.visibleY);
         var mounted:Boolean = false;
         try
         {
            if(this.viewport.parent !== this.mount) this.mount.addChild(this.viewport);
            mounted = true;
         }
         catch(mountError:*) { CanvasHtmlData.access = "render.attach"; }
         if(!mounted)
         {
            return new CanvasHtmlDiagnostic("render","attach-failed",this.loadResult.entryDocument.resource,-1,"viewport");
         }
         this.clipViewport(param2,param3,rendered.height);
         this.documentHeight = rendered.height;
         this.scrollOffset = Math.max(0,Math.min(Math.max(0,this.documentHeight - param3),this.scrollOffset));
         this.documentDisplay.y = -this.scrollOffset;
         if(this.hudTargets != null) this.hudTargets.apply(this.consumerId,rendered.targets);
         return null;
      }

      // A scroll area taller than the screen makes Scaleform drop the page. A mask keeps the same window.
      private function clipViewport(param1:Number, param2:Number, param3:Number) : void
      {
         var tallerThanScreen:Boolean = param3 > CanvasStageGuard.screenHeight || param1 > CanvasStageGuard.screenWidth;
         if(!tallerThanScreen)
         {
            this.viewport.mask = null;
            if(this.viewportMask != null && this.viewportMask.parent != null) this.viewportMask.parent.removeChild(this.viewportMask);
            this.viewport.scrollRect = new Rectangle(0,0,param1,param2);
            return;
         }
         this.viewport.scrollRect = null;
         if(this.viewportMask == null)
         {
            this.viewportMask = new Shape();
            this.viewportMask.name = "CanvasHtmlViewportMask";
         }
         this.viewportMask.graphics.clear();
         this.viewportMask.graphics.beginFill(0,1);
         this.viewportMask.graphics.drawRect(0,0,param1,param2);
         this.viewportMask.graphics.endFill();
         this.viewportMask.x = this.viewport.x;
         this.viewportMask.y = this.viewport.y;
         if(this.viewportMask.parent !== this.mount) this.mount.addChild(this.viewportMask);
         this.viewport.mask = this.viewportMask;
      }

      // The menu builds this page before its loader is on the pause menu. Repaint once that loader is showing.
      public function paintOnStage() : String
      {
         if(this.disposed || this.viewport == null)
         {
            return "missing";
         }
         if(this.viewport.stage == null)
         {
            return "waiting";
         }
         if(this.stagePainted)
         {
            return "ok | height " + this.documentHeight;
         }
         this.retainedBoxes = null;
         var status:String = "ok | height " + this.documentHeight;
         try
         {
            var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,this.viewportWidth,this.viewportHeight,this.activeState);
            if(failure != null)
            {
               status = failure.toString();
            }
            else
            {
               this.stagePainted = true;
            }
         }
         catch(stagePaintError:*)
         {
            status = String(stagePaintError).substr(0,180);
         }
         return status;
      }

      private function indexEventStates() : CanvasHtmlDiagnostic
      {
         this.eventStates = {};
         this.stateEvents = {};
         var resource:CanvasHtmlResource = null;
         for each(resource in this.loadResult.resources)
         {
            if(resource.document == null || resource.document.root == null)
            {
               continue;
            }
            var nodes:Array = [resource.document.root];
            while(nodes.length > 0)
            {
               var node:CanvasHtmlNode = nodes.pop() as CanvasHtmlNode;
               if(node.type == CanvasHtmlNode.ELEMENT && node.name == "vw-state" && node.getAttribute("event") != null)
               {
                  var eventName:String = node.getAttribute("event");
                  var stateName:String = node.getAttribute("name");
                  if(this.eventStates.hasOwnProperty(eventName) || this.stateEvents.hasOwnProperty(stateName))
                  {
                     return new CanvasHtmlDiagnostic("compose","duplicate-event-state",node.resource,node.referenceOffset);
                  }
                  this.eventStates[eventName] = stateName;
                  this.stateEvents[stateName] = eventName;
               }
               for(var index:int = node.children.length - 1; index >= 0; index--)
               {
                  nodes.push(node.children[index]);
               }
            }
         }
         return null;
      }

      private function isEventTopic(param1:String) : Boolean
      {
         if(param1 == null || param1.length < 3 || param1.length > CanvasHtmlLimits.MAX_EVENT_TOPIC_CODE_UNITS || !/^[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?(\.[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?)+$/.test(param1))
         {
            return false;
         }
         return param1.substr(0,7).toLowerCase() != "canvas.";
      }
   }
}
