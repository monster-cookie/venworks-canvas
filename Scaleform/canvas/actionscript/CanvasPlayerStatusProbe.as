package
{
   import flash.events.TimerEvent;
   import flash.utils.Timer;

   public final class CanvasPlayerStatusProbe
   {
      private static const CHANNEL:String = "PlayerStatusData";

      private static const MAX_ENTRIES:int = 64;

      private var dataManager:Object;

      private var report:Function;

      private var callback:Function;

      private var timer:Timer;

      private var lastLine:String;

      private var armed:Boolean = false;

      private var subscribed:Boolean = false;

      private var disposed:Boolean = false;

      public function CanvasPlayerStatusProbe(dataManager:Object, report:Function)
      {
         var probe:CanvasPlayerStatusProbe = this;
         this.dataManager = dataManager;
         this.report = report;
         this.callback = function(payload:Object):void
         {
            probe.onPayload(payload);
         };
      }

      public function start() : void
      {
         if(this.disposed || this.armed)
         {
            return;
         }
         this.armed = true;
         this.attempt();
         this.ensureTimer();
      }

      public function attempt() : void
      {
         var provider:Object = null;
         if(this.disposed || this.subscribed)
         {
            return;
         }
         if(this.dataManager == null)
         {
            this.reportLine("PLAYER_STATUS_DATA ERROR data manager missing");
            this.ensureTimer();
            return;
         }
         try
         {
            provider = this.dataManager.GetDataFromClient(CHANNEL,true);
         }
         catch(readError:*)
         {
            this.reportLine("PLAYER_STATUS_DATA ERROR " + this.safeText(readError));
            this.ensureTimer();
            return;
         }
         if(provider == null)
         {
            this.reportLine("PLAYER_STATUS_DATA UNAVAILABLE");
            this.ensureTimer();
            return;
         }
         // Record ownership before Subscribe. A ready provider may replay during the call.
         this.subscribed = true;
         this.stopTimer();
         try
         {
            this.dataManager.Subscribe(CHANNEL,this.callback);
         }
         catch(subscribeError:*)
         {
            this.subscribed = false;
            this.releaseSubscription();
            this.reportLine("PLAYER_STATUS_DATA ERROR " + this.safeText(subscribeError));
            this.ensureTimer();
         }
      }

      public function dispose() : void
      {
         var wasSubscribed:Boolean = false;
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         wasSubscribed = this.subscribed;
         this.subscribed = false;
         this.stopTimer();
         if(wasSubscribed)
         {
            this.releaseSubscription();
         }
         this.dataManager = null;
         this.report = null;
      }

      private function onPayload(payload:Object) : void
      {
         if(this.disposed || !this.subscribed)
         {
            return;
         }
         this.reportLine(this.summarize(payload));
      }

      private function ensureTimer() : void
      {
         if(!this.armed || this.disposed || this.subscribed || this.timer != null)
         {
            return;
         }
         this.timer = new Timer(1000);
         this.timer.addEventListener(TimerEvent.TIMER,this.onTimer);
         this.timer.start();
      }

      private function onTimer(event:TimerEvent) : void
      {
         this.attempt();
      }

      private function stopTimer() : void
      {
         if(this.timer == null)
         {
            return;
         }
         this.timer.stop();
         this.timer.removeEventListener(TimerEvent.TIMER,this.onTimer);
         this.timer = null;
      }

      private function releaseSubscription() : void
      {
         if(this.dataManager == null || this.callback == null)
         {
            return;
         }
         try
         {
            this.dataManager.Unsubscribe(CHANNEL,this.callback);
         }
         catch(cleanupError:*)
         {
         }
      }

      private function reportLine(message:String) : void
      {
         if(this.disposed || message == this.lastLine || this.report == null)
         {
            return;
         }
         this.lastLine = message;
         try
         {
            this.report(message);
         }
         catch(reportError:*)
         {
         }
      }

      private function summarize(payload:Object) : String
      {
         var data:Object = this.payloadData(payload);
         var groups:* = this.readProperty(data,"aEffectGroups");
         var groupCount:int = this.collectionCount(groups);
         var effectCount:int = 0;
         var timerCount:int = 0;
         var iconCount:int = 0;
         var groupIndex:int = 0;
         var effectTotal:int = 0;
         var effectIndex:int = 0;
         var group:Object = null;
         var effects:* = null;
         var effect:Object = null;
         if(groupCount < 0)
         {
            groupCount = 0;
         }
         while(groupIndex < groupCount)
         {
            group = this.itemAt(groups,groupIndex);
            if(this.hasIcon(group))
            {
               iconCount++;
            }
            if(this.hasGroupTimer(group))
            {
               timerCount++;
            }
            effects = this.readProperty(group,"aEffects");
            effectTotal = this.collectionCount(effects);
            if(effectTotal < 0)
            {
               effectTotal = 0;
            }
            effectCount += effectTotal;
            effectIndex = 0;
            while(effectIndex < effectTotal)
            {
               effect = this.itemAt(effects,effectIndex);
               if(this.hasIcon(effect))
               {
                  iconCount++;
               }
               if(this.hasEffectTimer(effect))
               {
                  timerCount++;
               }
               effectIndex++;
            }
            groupIndex++;
         }
         return "PLAYER_STATUS_DATA groups=" + groupCount + " effects=" + effectCount + " timers=" + timerCount + " icons=" + iconCount;
      }

      private function payloadData(payload:Object) : Object
      {
         var wrapped:* = null;
         if(payload == null)
         {
            return null;
         }
         wrapped = this.readProperty(payload,"data");
         if(wrapped is Object && wrapped != null)
         {
            return wrapped as Object;
         }
         return payload;
      }

      private function collectionCount(value:*) : int
      {
         var count:Number = NaN;
         if(value == null)
         {
            return -1;
         }
         if(value is Array)
         {
            count = (value as Array).length;
         }
         else
         {
            try
            {
               count = Number(value.length);
            }
            catch(lengthError:*)
            {
               return -1;
            }
         }
         if(!isFinite(count) || count < 0 || count != Math.floor(count))
         {
            return -1;
         }
         if(count > MAX_ENTRIES)
         {
            count = MAX_ENTRIES;
         }
         return int(count);
      }

      private function itemAt(value:*, index:int) : Object
      {
         var item:* = null;
         try
         {
            item = value[index];
            if(item is Object)
            {
               return item as Object;
            }
         }
         catch(indexError:*)
         {
         }
         return null;
      }

      private function readProperty(value:Object, name:String) : *
      {
         if(value == null)
         {
            return null;
         }
         try
         {
            return value[name];
         }
         catch(readError:*)
         {
            return null;
         }
      }

      private function hasIcon(value:Object) : Boolean
      {
         var icon:* = this.readProperty(value,"sEffectIcon");
         return icon != null && String(icon).length > 0;
      }

      private function hasGroupTimer(value:Object) : Boolean
      {
         if(this.readProperty(value,"bShowTimer") !== true)
         {
            return false;
         }
         return this.isFiniteNumber(this.readProperty(value,"fTimeRemaining"));
      }

      private function hasEffectTimer(value:Object) : Boolean
      {
         if(value == null || this.readProperty(value,"bPermanent") === true)
         {
            return false;
         }
         return this.isFiniteNumber(this.readProperty(value,"fTimeRemaining"));
      }

      private function isFiniteNumber(value:*) : Boolean
      {
         var number:Number = NaN;
         if(value == null || value is String || value is Boolean)
         {
            return false;
         }
         number = Number(value);
         return isFinite(number);
      }

      private function safeText(value:*) : String
      {
         var text:String = "unknown";
         try
         {
            text = String(value);
         }
         catch(textError:*)
         {
            return "unknown";
         }
         text = text.split("\r").join(" ").split("\n").join(" ");
         if(text.length > 120)
         {
            text = text.substr(0,120);
         }
         return text;
      }
   }
}
