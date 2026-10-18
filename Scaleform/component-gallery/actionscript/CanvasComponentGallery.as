package
{
   import flash.display.MovieClip;
   import flash.events.Event;

   public final class CanvasComponentGallery extends MovieClip
   {
      private static const DEFAULT_VIEWPORT_WIDTH:Number = 1920;

      private static const DEFAULT_VIEWPORT_HEIGHT:Number = 1080;

      private static const MAX_LIST_ITEMS:int = 64;

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
            "uiChannels":["PlayerData","PlayerFrequentData","QuestData"],
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
         else if(param1 == "QuestData")
         {
            this.captureQuestData(param2);
            this.submitSampleData();
            return;
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
            "samplex":18,
            "sampley":2,
            "samplerotation":2,
            "sampleopacity":0.85,
            "samplescale":1,
            "sampleasset":"gallery-icon.svg",
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

      private function captureQuestData(param1:Object) : void
      {
         delete this.playerValues["quest.title"];
         delete this.playerValues["quest.waypoint"];
         delete this.playerValues["quest.waypoints"];
         var quests:Array = this.readList(param1,"aQuests");
         if(quests == null)
         {
            return;
         }
         var active:Object = this.findActiveQuest(quests);
         if(active == null)
         {
            return;
         }
         var title:String = this.readTitle(active,"sName");
         if(title != null)
         {
            this.playerValues["quest.title"] = title;
         }
         this.playerValues["quest.waypoints"] = this.readWaypointTitles(active);
         var current:String = this.readCurrentWaypoint(active);
         if(current != null)
         {
            this.playerValues["quest.waypoint"] = current;
         }
      }

      private function findActiveQuest(param1:Array) : Object
      {
         var active:Object = null;
         var count:int = int(Math.min(MAX_LIST_ITEMS,Number(param1.length)));
         var index:int = 0;
         while(index < count)
         {
            var quest:* = param1[index];
            if(quest != null && typeof quest == "object" && !(quest is Array) && this.flagIsTrue(quest,"bActive"))
            {
               active = quest;
            }
            index++;
         }
         return active;
      }

      private function readWaypointTitles(param1:Object) : Array
      {
         var titles:Array = [];
         var source:Array = this.readList(param1,"aObjectives");
         if(source == null)
         {
            return titles;
         }
         var count:int = int(Math.min(MAX_LIST_ITEMS,Number(source.length)));
         var index:int = 0;
         while(index < count)
         {
            var item:* = source[index];
            if(item != null && typeof item == "object" && !(item is Array))
            {
               var title:String = this.readTitle(item,"sName");
               if(title != null)
               {
                  titles.push(title);
               }
            }
            index++;
         }
         return titles;
      }

      private function readCurrentWaypoint(param1:Object) : String
      {
         var source:Array = this.readList(param1,"aObjectives");
         if(source == null)
         {
            return null;
         }
         var count:int = int(Math.min(MAX_LIST_ITEMS,Number(source.length)));
         var index:int = 0;
         var found:Boolean = false;
         var text:String = "";
         while(index < count)
         {
            var item:* = source[index];
            if(item != null && typeof item == "object" && !(item is Array))
            {
               if(found && this.flagIsFalse(item,"bORWithPrevious"))
               {
                  break;
               }
               if(this.flagIsTrue(item,"bActive") && !this.flagIsTrue(item,"bComplete") && !this.flagIsTrue(item,"bFailed"))
               {
                  var title:String = this.readTitle(item,"sName");
                  if(title != null)
                  {
                     if(found)
                     {
                        text += " | " + title;
                        break;
                     }
                     text = title;
                     found = true;
                  }
               }
            }
            index++;
         }
         return found ? text : null;
      }

      private function readList(param1:Object, param2:String) : Array
      {
         if(param1 == null)
         {
            return null;
         }
         var value:* = undefined;
         try
         {
            if(!(param2 in param1))
            {
               return null;
            }
            value = param1[param2];
         }
         catch(readError:*)
         {
            return null;
         }
         if(value == null || typeof value != "object")
         {
            return null;
         }
         var lengthValue:* = undefined;
         try
         {
            lengthValue = value.length;
         }
         catch(lengthError:*)
         {
            return null;
         }
         var count:Number = Number(lengthValue);
         if(!isFinite(count) || count < 0 || int(count) != count || count > 256)
         {
            return null;
         }
         var copy:Array = [];
         var index:int = 0;
         var limit:int = int(Math.min(MAX_LIST_ITEMS,count));
         while(index < limit)
         {
            try
            {
               copy.push(value[index]);
            }
            catch(itemError:*)
            {
               break;
            }
            index++;
         }
         return copy;
      }

      private function readTitle(param1:Object, param2:String) : String
      {
         var raw:* = this.readField(param1,param2);
         if(typeof raw != "string")
         {
            return null;
         }
         var value:String = String(raw).split("\\n").join("").split("\\N").join("");
         if(value.length == 0 || value.length > 256)
         {
            return null;
         }
         return value;
      }

      private function readField(param1:Object, param2:String) : *
      {
         try
         {
            if(param1 == null || !(param2 in param1))
            {
               return undefined;
            }
            return param1[param2];
         }
         catch(readError:*)
         {
         }
         return undefined;
      }

      private function flagIsTrue(param1:Object, param2:String) : Boolean
      {
         return this.readField(param1,param2) === true;
      }

      private function flagIsFalse(param1:Object, param2:String) : Boolean
      {
         return this.readField(param1,param2) === false;
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
