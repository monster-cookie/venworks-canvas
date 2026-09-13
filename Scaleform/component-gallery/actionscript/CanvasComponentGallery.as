package
{
   import flash.display.MovieClip;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.ui.Keyboard;

   public final class CanvasComponentGallery extends MovieClip
   {
      private static const DEFAULT_VIEWPORT_WIDTH:Number = 1920;

      private static const DEFAULT_VIEWPORT_HEIGHT:Number = 1080;

      private static const LINE_SCROLL:Number = 64;

      private static const PAGE_SCROLL:Number = 720;

      private var htmlBridge:Object;

      private var inputStage:Stage;

      private var playerDataUpdates:int;

      public function CanvasComponentGallery()
      {
         super();
         this.addEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage,false,0,true);
         this.addEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage,false,0,true);
      }

      public function getCanvasRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/2",
            "consumerId":"beef70b2-024e-4e9b-a8d5-70a0c882c431",
            "assetNamespace":"venworks.canvas.component-gallery",
            "version":1,
            "minimumContractVersion":2,
            "maximumContractVersion":2,
            "uiChannels":["PlayerData"],
            "eventTopics":["venworks.canvas.example.ping"],
            "marker":"COMPONENT-GALLERY"
         };
      }

      public function getCanvasHtmlRegistration() : Object
      {
         return {
            "contract":"VWCANVAS_HTML/2",
            "entryDocument":"index.html"
         };
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
         if(param1 == "PlayerData")
         {
            this.playerDataUpdates = this.playerDataUpdates >= 9999 ? 0 : this.playerDataUpdates + 1;
            this.submitSampleData();
         }
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         if(this.htmlBridge != null && param1 == "venworks.canvas.example.ping")
         {
            try
            {
               this.htmlBridge["dispatch"](param1);
            }
            catch(dispatchError:*)
            {
               this.clearHtmlBridge();
            }
         }
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(param1 == "ready")
         {
            this.clearHtmlBridge();
            this.playerDataUpdates = 0;
            this.htmlBridge = this.resolveHtmlBridge(param2);
            if(this.htmlBridge != null)
            {
               this.updateViewport();
               this.submitSampleData();
               this.attachInputListeners();
            }
         }
         else if(param1 == "unload")
         {
            this.clearHtmlBridge();
         }
      }

      public function dispose() : void
      {
         this.clearHtmlBridge();
         this.removeEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage);
         this.removeEventListener(Event.REMOVED_FROM_STAGE,this.onRemovedFromStage);
      }

      private function resolveHtmlBridge(param1:Object) : Object
      {
         if(param1 == null || !("features" in param1) || !("html" in param1))
         {
            return null;
         }
         var features:Array = param1["features"] as Array;
         var bridge:Object = param1["html"];
         if(features == null || features.indexOf("htmlRendering") < 0 || bridge == null)
         {
            return null;
         }
         if(!("setData" in bridge) || typeof bridge["setData"] != "function" || !("setViewport" in bridge) || typeof bridge["setViewport"] != "function" || !("scrollBy" in bridge) || typeof bridge["scrollBy"] != "function" || !("dispatch" in bridge) || typeof bridge["dispatch"] != "function")
         {
            return null;
         }
         return bridge;
      }

      private function createSampleData() : Object
      {
         return {
            "sampletext":"Bound through Canvas data",
            "sampleformat":42,
            "samplevisible":true,
            "sampleitems":["Alpha item","Beta item","Gamma item"],
            "samplemeter":72,
            "sampleupdates":"PlayerData snapshots received: " + this.playerDataUpdates
         };
      }

      private function submitSampleData() : void
      {
         if(this.htmlBridge != null)
         {
            this.htmlBridge["setData"](this.createSampleData());
         }
      }

      private function updateViewport() : void
      {
         if(this.htmlBridge == null)
         {
            return;
         }
         var viewportWidth:Number = DEFAULT_VIEWPORT_WIDTH;
         var viewportHeight:Number = DEFAULT_VIEWPORT_HEIGHT;
         if(stage != null)
         {
            if(stage.stageWidth > 0 && stage.stageWidth <= 4096)
            {
               viewportWidth = stage.stageWidth;
            }
            if(stage.stageHeight > 0 && stage.stageHeight <= 4096)
            {
               viewportHeight = stage.stageHeight;
            }
         }
         this.htmlBridge["setViewport"](viewportWidth,viewportHeight);
      }

      private function attachInputListeners() : void
      {
         if(this.htmlBridge == null || stage == null || this.inputStage === stage)
         {
            return;
         }
         this.detachInputListeners();
         this.inputStage = stage;
         this.inputStage.addEventListener(MouseEvent.MOUSE_WHEEL,this.onMouseWheel,false,0,true);
         this.inputStage.addEventListener(KeyboardEvent.KEY_DOWN,this.onKeyDown,false,0,true);
         this.inputStage.addEventListener(Event.RESIZE,this.onStageResize,false,0,true);
      }

      private function detachInputListeners() : void
      {
         if(this.inputStage == null)
         {
            return;
         }
         this.inputStage.removeEventListener(MouseEvent.MOUSE_WHEEL,this.onMouseWheel);
         this.inputStage.removeEventListener(KeyboardEvent.KEY_DOWN,this.onKeyDown);
         this.inputStage.removeEventListener(Event.RESIZE,this.onStageResize);
         this.inputStage = null;
      }

      private function clearHtmlBridge() : void
      {
         this.detachInputListeners();
         this.htmlBridge = null;
      }

      private function scrollHtml(param1:Number) : void
      {
         if(this.htmlBridge == null)
         {
            return;
         }
         try
         {
            this.htmlBridge["scrollBy"](param1);
         }
         catch(scrollError:*)
         {
            this.clearHtmlBridge();
         }
      }

      private function onAddedToStage(param1:Event) : void
      {
         if(this.htmlBridge != null)
         {
            try
            {
               this.updateViewport();
               this.attachInputListeners();
            }
            catch(viewportError:*)
            {
               this.clearHtmlBridge();
            }
         }
      }

      private function onRemovedFromStage(param1:Event) : void
      {
         this.detachInputListeners();
      }

      private function onStageResize(param1:Event) : void
      {
         try
         {
            this.updateViewport();
         }
         catch(viewportError:*)
         {
            this.clearHtmlBridge();
         }
      }

      private function onMouseWheel(param1:MouseEvent) : void
      {
         var delta:Number = param1.delta;
         if(delta > 3)
         {
            delta = 3;
         }
         else if(delta < -3)
         {
            delta = -3;
         }
         this.scrollHtml(-delta * LINE_SCROLL);
      }

      private function onKeyDown(param1:KeyboardEvent) : void
      {
         if(param1.keyCode == Keyboard.UP)
         {
            this.scrollHtml(-LINE_SCROLL);
         }
         else if(param1.keyCode == Keyboard.DOWN)
         {
            this.scrollHtml(LINE_SCROLL);
         }
         else if(param1.keyCode == Keyboard.PAGE_UP)
         {
            this.scrollHtml(-PAGE_SCROLL);
         }
         else if(param1.keyCode == Keyboard.PAGE_DOWN)
         {
            this.scrollHtml(PAGE_SCROLL);
         }
      }
   }
}
