package
{
   import flash.display.MovieClip;
   import flash.events.TimerEvent;
   import flash.utils.Timer;

   public final class CanvasExample extends MovieClip
   {
      private var htmlBridge:Object;
      private var effects:CanvasExampleEffectsAdapter = new CanvasExampleEffectsAdapter();
      private var pageTimer:Timer;
      private var inSpaceship:Boolean;
      private var localPlanetTime:Number = NaN;
      private var galacticStandardTime:Number = NaN;
      private var universalClock:String = "--:--";
      private var localClock:String = "--:--";

      public function getCanvasRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/3",
            "consumerId":"a8098c1a-f86e-4b1e-9d7c-5a102bf38460",
            "assetNamespace":"venworks.canvas.example",
            "version":1,
            "minimumContractVersion":3,
            "maximumContractVersion":3,
            "uiChannels":["LocalEnvironmentData","LocalEnvData_Frequent"],
            "eventSubscriptions":[{"topic":"venworks.canvas.example.status","startup":"latest"}],
            "marker":"EXAMPLE"
         };
      }

      public function getCanvasHtmlRegistration() : Object
      {
         return {"contract":"VWCANVAS_HTML/2","entryDocument":"index.html"};
      }

      public function handleUIData(channel:String, data:Object) : void
      {
         if(channel == "LocalEnvironmentData")
         {
            this.inSpaceship = this.booleanValue(data,"bInSpaceship");
         }
         else if(channel == "LocalEnvData_Frequent")
         {
            this.localPlanetTime = this.numberValue(data,"fLocalPlanetTime",0,1);
            this.galacticStandardTime = this.numberValue(data,"fGalacticStandardTime",0,24);
         }
         else
         {
            return;
         }
         var nextUniversal:String = this.formatClock(this.galacticStandardTime);
         var nextLocal:String = this.inSpaceship ? "--:--" : this.formatClock(this.localPlanetTime * 24);
         if(nextUniversal != this.universalClock || nextLocal != this.localClock)
         {
            this.universalClock = nextUniversal;
            this.localClock = nextLocal;
            this.publish();
         }
      }

      public function handleCanvasEvent(topic:String, body:String) : void
      {
         if(topic == "venworks.canvas.example.status" && this.effects.acceptDatagram(body))
         {
            this.publish();
         }
      }

      public function handleLifecycle(state:String, detail:Object) : void
      {
         if(state == "ready")
         {
            this.stopPageTimer();
            this.effects.reset();
            this.resetClock();
            this.htmlBridge = this.resolveHtmlBridge(detail);
            if(this.htmlBridge == null)
            {
               throw new Error("Canvas Example requires the Canvas HTML bridge");
            }
            if(stage != null && stage.stageWidth >= 64 && stage.stageHeight >= 64 && stage.stageWidth <= 8192 && stage.stageHeight <= 8192)
            {
               this.htmlBridge["setViewport"](stage.stageWidth,stage.stageHeight);
            }
            this.publish();
            this.pageTimer = new Timer(6000);
            this.pageTimer.addEventListener(TimerEvent.TIMER,this.advancePage);
            this.pageTimer.start();
         }
         else if(state == "unload")
         {
            this.stopPageTimer();
            this.htmlBridge = null;
            this.effects.reset();
            this.resetClock();
         }
      }

      public function dispose() : void
      {
         this.stopPageTimer();
         this.htmlBridge = null;
         this.effects.reset();
         this.resetClock();
      }

      private function resetClock() : void
      {
         this.inSpaceship = false;
         this.localPlanetTime = NaN;
         this.galacticStandardTime = NaN;
         this.universalClock = "--:--";
         this.localClock = "--:--";
      }

      private function resolveHtmlBridge(detail:Object) : Object
      {
         if(detail == null || !("features" in detail) || !("html" in detail))
         {
            return null;
         }
         var features:Array = detail["features"] as Array;
         var bridge:Object = detail["html"];
         if(features == null || features.indexOf("htmlRendering") < 0 || bridge == null)
         {
            return null;
         }
         if(!("setData" in bridge) || typeof bridge["setData"] != "function" || !("setViewport" in bridge) || typeof bridge["setViewport"] != "function")
         {
            return null;
         }
         return bridge;
      }

      private function publish() : void
      {
         if(this.htmlBridge == null)
         {
            return;
         }
         var data:Object = this.effects.view();
         data["universaltime"] = this.universalClock + " UT";
         data["localtime"] = this.localClock;
         this.htmlBridge["setData"](data);
      }

      private function advancePage(event:TimerEvent) : void
      {
         if(this.effects.advancePage())
         {
            this.publish();
         }
      }

      private function stopPageTimer() : void
      {
         if(this.pageTimer != null)
         {
            this.pageTimer.stop();
            this.pageTimer.removeEventListener(TimerEvent.TIMER,this.advancePage);
            this.pageTimer = null;
         }
      }

      private function formatClock(hours:Number) : String
      {
         if(!isFinite(hours))
         {
            return "--:--";
         }
         var normalized:Number = hours % 24;
         if(normalized < 0)
         {
            normalized += 24;
         }
         var minutes:int = Math.floor(normalized * 60) % 1440;
         return this.pad(Math.floor(minutes / 60)) + ":" + this.pad(minutes % 60);
      }

      private function pad(value:int) : String
      {
         return value < 10 ? "0" + value : String(value);
      }

      private function numberValue(data:Object, field:String, minimum:Number, maximum:Number) : Number
      {
         try
         {
            if(data != null && field in data)
            {
               var value:Number = Number(data[field]);
               if(isFinite(value) && value >= minimum && value <= maximum)
               {
                  return value;
               }
            }
         }
         catch(valueError:*)
         {
         }
         return NaN;
      }

      private function booleanValue(data:Object, field:String) : Boolean
      {
         try
         {
            return data != null && field in data && data[field] === true;
         }
         catch(valueError:*)
         {
         }
         return false;
      }
   }
}
