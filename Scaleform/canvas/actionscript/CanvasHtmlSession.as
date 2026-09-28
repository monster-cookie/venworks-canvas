package
{
   import flash.display.DisplayObjectContainer;
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
            var text:String = "";
            try { text = String(rebuildError); } catch(ignored:*) { text = ""; }
            if(this.documentDisplay == null || text.indexOf("#1069") < 0 && text.indexOf("1069 ") != 0) throw rebuildError;
         }
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
         var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,param1,param2,this.activeState);
         if(failure != null)
         {
            throw new Error(failure.toString());
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
         var failure:CanvasHtmlDiagnostic = this.rebuild(this.data,this.viewportWidth,this.viewportHeight,nextState);
         if(failure != null)
         {
            throw new Error(failure.toString());
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
         if(this.hudTargets != null) this.hudTargets.release(this.consumerId);
         this.hudTargets = null;
         if(this.viewport != null)
         {
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
         this.retainedBoxes = null;
         this.documentDisplay = null;
         this.viewport = null;
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
         CanvasHtmlRetainedTree.commit(rendered.boxes);
         rendered.display = rendered.boxes[0].sprite as Sprite;
         this.retainedBoxes = rendered.boxes;
         if(this.viewport == null)
         {
            this.viewport = new Sprite();
            this.viewport.name = "CanvasHtmlViewport";
            this.viewport.mouseEnabled = false;
            this.viewport.mouseChildren = false;
         }
         if(this.documentDisplay != null && this.documentDisplay !== rendered.display && this.documentDisplay.parent === this.viewport)
         {
            this.viewport.removeChild(this.documentDisplay);
         }
         this.documentDisplay = rendered.display;
         this.documentDisplay.name = "CanvasHtmlDocument";
         try { if(this.documentDisplay.parent !== this.viewport) this.viewport.addChild(this.documentDisplay); }
         catch(attachError:*) { CanvasHtmlData.access = "render.attach"; }
         this.viewport.scrollRect = new Rectangle(0,0,param2,param3);
         this.viewport.x = this.hostLayout == null ? 0 : Number(this.hostLayout.visibleX);
         this.viewport.y = this.hostLayout == null ? 0 : Number(this.hostLayout.visibleY);
         try { if(this.viewport.parent !== this.mount) this.mount.addChild(this.viewport); }
         catch(mountError:*) { CanvasHtmlData.access = "render.attach"; }
         this.documentHeight = rendered.height;
         this.scrollOffset = Math.max(0,Math.min(Math.max(0,this.documentHeight - param3),this.scrollOffset));
         this.documentDisplay.y = -this.scrollOffset;
         if(this.hudTargets != null) this.hudTargets.apply(this.consumerId,rendered.targets);
         return null;
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
