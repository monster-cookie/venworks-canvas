package
{
   import flash.display.MovieClip;
   import flash.events.Event;

   public final class CanvasComponentGallery extends MovieClip
   {
      private static const DEFAULT_VIEWPORT_WIDTH:Number = 1920;

      private static const DEFAULT_VIEWPORT_HEIGHT:Number = 1080;

      private var htmlBridge:Object;

      private var playerDataUpdates:int;

      private var playerValues:Object = {};

      private var hostKind:String = "";

      public function CanvasComponentGallery()
      {
         super();
         this.addEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage,false,0,true);
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
            "hostKinds":["menu"],
            "uiChannels":["PlayerData","PlayerFrequentData"],
            "eventTopics":[],
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
            this.capturePlayerData(param2);
         }
         else if(param1 == "PlayerFrequentData")
         {
            this.capturePlayerFrequentData(param2);
         }
         else
         {
            return;
         }
         this.playerDataUpdates = this.playerDataUpdates >= 9999 ? 0 : this.playerDataUpdates + 1;
         this.submitSampleData();
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
            this.playerValues = {};
            this.hostKind = param2 != null && "hostKind" in param2 ? String(param2["hostKind"]) : "";
            this.htmlBridge = this.resolveHtmlBridge(param2);
            if(this.htmlBridge != null)
            {
               this.updateViewport();
               this.submitSampleData();
            }
         }
         else if(param1 == "unload")
         {
            this.hostKind = "";
            this.playerValues = {};
            this.clearHtmlBridge();
         }
      }

      public function dispose() : void
      {
         this.clearHtmlBridge();
         this.removeEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage);
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
         if(!("setData" in bridge) || typeof bridge["setData"] != "function" || !("setViewport" in bridge) || typeof bridge["setViewport"] != "function" || !("dispatch" in bridge) || typeof bridge["dispatch"] != "function")
         {
            return null;
         }
         return bridge;
      }

      private function createSampleData() : Object
      {
         var result:Object = {
            "sampletext":"Bound through Canvas data",
            "sampleformat":42,
            "samplevisible":true,
            "sampleitems":["Alpha item","Beta item","Gamma item"],
            "samplemeter":72,
            "sampleupdates":this.hostKind == "menu" ? "Menu-local sample data" : "PlayerData snapshots received: " + this.playerDataUpdates
         };
         var key:String = null;
         for(key in this.playerValues)
         {
            if(this.playerValues.hasOwnProperty(key))
            {
               result[key] = this.playerValues[key];
            }
         }
         return result;
      }

      private function capturePlayerData(param1:Object) : void
      {
         this.captureText("player.name",param1,"sName");
         this.captureFinite("player.level",param1,"uLevel");
         this.captureFinite("player.levelxp",param1,"fLevelXP");
         this.captureFinite("player.nextlevelxp",param1,"fNextLevelXP");
         this.captureRatio("player.xppercentage",param1,"fLevelXP","fNextLevelXP");
      }

      private function capturePlayerFrequentData(param1:Object) : void
      {
         this.captureFinite("player.health",param1,"fHealth");
         this.captureFinite("player.maxhealth",param1,"fMaxHealth");
         this.captureRatio("player.healthpercentage",param1,"fHealth","fMaxHealth");
         this.captureFinite("player.oxygen",param1,"fOxygen");
         this.captureFinite("player.maxoxygen",param1,"fMaxO2CO2");
         this.captureRatio("player.oxygenpercentage",param1,"fOxygen","fMaxO2CO2");
         this.captureFinite("player.carbondioxide",param1,"fCarbonDioxide");
         this.captureRatio("player.carbondioxidepercentage",param1,"fCarbonDioxide","fMaxO2CO2");
         this.captureFinite("power.current",param1,"fStarPower");
         this.captureFinite("power.maximum",param1,"fMaxStarPower");
         this.captureRatio("power.percentage",param1,"fStarPower","fMaxStarPower");
      }

      private function captureText(param1:String, param2:Object, param3:String) : void
      {
         if(param2 == null || !(param3 in param2) || param2[param3] == null)
         {
            delete this.playerValues[param1];
            return;
         }
         var value:String = String(param2[param3]);
         if(value.length > 256)
         {
            delete this.playerValues[param1];
            return;
         }
         this.playerValues[param1] = value;
      }

      private function captureFinite(param1:String, param2:Object, param3:String) : void
      {
         if(param2 == null || !(param3 in param2) || typeof param2[param3] != "number" || !isFinite(Number(param2[param3])))
         {
            delete this.playerValues[param1];
            return;
         }
         this.playerValues[param1] = Number(param2[param3]);
      }

      private function captureRatio(param1:String, param2:Object, param3:String, param4:String) : void
      {
         if(param2 == null || !(param3 in param2) || !(param4 in param2) || typeof param2[param3] != "number" || typeof param2[param4] != "number")
         {
            delete this.playerValues[param1];
            return;
         }
         var current:Number = Number(param2[param3]);
         var maximum:Number = Number(param2[param4]);
         if(!isFinite(current) || !isFinite(maximum) || maximum <= 0)
         {
            delete this.playerValues[param1];
            return;
         }
         this.playerValues[param1] = Math.max(0,Math.min(100,current / maximum * 100));
      }

      private function submitSampleData() : void
      {
         if(this.htmlBridge != null)
         {
            this.htmlBridge["setData"](this.createSampleData());
            if(this.hostKind == "menu")
            {
               this.htmlBridge["dispatch"]("venworks.canvas.example.ping");
            }
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

      private function clearHtmlBridge() : void
      {
         this.htmlBridge = null;
      }

      private function onAddedToStage(param1:Event) : void
      {
         if(this.htmlBridge != null)
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
      }

   }
}
