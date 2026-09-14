package
{
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.utils.getTimer;

   internal final class CanvasChronomarkAnimation
   {
      private var clockSource:Sprite;

      private var view:CanvasChronomarkView;

      private var effects:CanvasChronomarkEffects;

      private var sound:Function;

      private var alertQueue:Array;

      private var activeAlert:Object;

      private var alertPhase:String = "";

      private var alertElapsed:Number = 0;

      private var scannerAlpha:Number = 1;

      private var scannerTarget:Number = 1;

      private var scannerHoldRemaining:Number = 0;

      private var detectionAlpha:Number = 0;

      private var detectionTarget:Number = 0;

      private var clockRunning:Boolean = false;

      private var lastTime:int = 0;

      private var disposed:Boolean = false;

      public function CanvasChronomarkAnimation(param1:Sprite, param2:CanvasChronomarkView, param3:CanvasChronomarkEffects, param4:Function)
      {
         this.clockSource = param1;
         this.view = param2;
         this.effects = param3;
         this.sound = param4;
         this.alertQueue = [];
      }

      public function enqueuePersonalAlerts(param1:Array, param2:Number) : void
      {
         this.enqueueAlerts("personal",param1,param2);
      }

      public function enqueueEnvironmentAlerts(param1:Array, param2:Number) : void
      {
         this.enqueueAlerts("environment",param1,param2);
      }

      public function setScannerState(param1:Boolean, param2:Boolean) : void
      {
         if(this.disposed)
         {
            return;
         }
         this.scannerTarget = param1 ? 1 : 0;
         this.scannerHoldRemaining = 0;
         if(param2)
         {
            this.scannerAlpha = this.scannerTarget;
            this.view.setScannerAlpha(this.scannerAlpha);
         }
         this.refreshClock();
      }

      public function showPlanetInformation(param1:Number) : void
      {
         if(this.disposed)
         {
            return;
         }
         this.scannerTarget = 1;
         this.scannerHoldRemaining = CanvasChronomarkStyle.clamp(param1,CanvasChronomarkStyle.MIN_DWELL_MS,CanvasChronomarkStyle.MAX_DWELL_MS);
         this.refreshClock();
      }

      public function setDetectionState(param1:Boolean, param2:Boolean) : void
      {
         if(this.disposed)
         {
            return;
         }
         this.detectionTarget = param1 ? 1 : 0;
         if(param2)
         {
            this.detectionAlpha = this.detectionTarget;
            this.view.setDetection(param1,this.detectionAlpha);
         }
         else if(param1)
         {
            this.view.setDetection(true,this.detectionAlpha);
         }
         this.refreshClock();
      }

      public function refreshPulseClock() : void
      {
         this.refreshClock();
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         this.stopClock();
         this.alertQueue = [];
         this.activeAlert = null;
         this.alertPhase = "";
         this.clockSource = null;
         this.view = null;
         this.effects = null;
         this.sound = null;
      }

      private function enqueueAlerts(param1:String, param2:Array, param3:Number) : void
      {
         if(this.disposed || param2 == null)
         {
            return;
         }
         var dwell:Number = CanvasChronomarkStyle.clamp(param3,CanvasChronomarkStyle.MIN_DWELL_MS,CanvasChronomarkStyle.MAX_DWELL_MS);
         var index:int = 0;
         while(index < param2.length && this.alertQueue.length + (this.activeAlert == null ? 0 : 1) < CanvasChronomarkStyle.ALERT_QUEUE_CAPACITY)
         {
            var source:Object = param2[index];
            var transaction:Object = {
               "kind":param1,
               "icon":String(source.icon),
               "heading":String(source.heading),
               "subtext":String(source.subtext),
               "positive":source.positive === true,
               "dwell":dwell
            };
            if(!this.isDuplicate(transaction))
            {
               this.alertQueue.push(transaction);
            }
            index++;
         }
         if(this.activeAlert == null)
         {
            this.beginNextAlert();
         }
         this.refreshClock();
      }

      private function isDuplicate(param1:Object) : Boolean
      {
         if(this.activeAlert != null && this.sameAlert(this.activeAlert,param1))
         {
            return true;
         }
         var index:int = 0;
         while(index < this.alertQueue.length)
         {
            if(this.sameAlert(this.alertQueue[index],param1))
            {
               return true;
            }
            index++;
         }
         return false;
      }

      private function sameAlert(param1:Object, param2:Object) : Boolean
      {
         return param1.kind == param2.kind && param1.icon == param2.icon && param1.heading == param2.heading && param1.subtext == param2.subtext && param1.positive == param2.positive;
      }

      private function beginNextAlert() : void
      {
         this.activeAlert = this.alertQueue.length > 0 ? this.alertQueue.shift() : null;
         this.alertElapsed = 0;
         if(this.activeAlert == null)
         {
            this.alertPhase = "";
            this.view.clearAlert();
            return;
         }
         this.alertPhase = "enter";
         this.view.showAlert(String(this.activeAlert.kind),String(this.activeAlert.heading),String(this.activeAlert.subtext),this.activeAlert.positive === true,0);
         this.playSound(CanvasChronomarkStyle.screenSoundForEffect(String(this.activeAlert.icon)));
         if(this.activeAlert.kind == "personal")
         {
            this.playSound("UIAfflictionPainWarningScreenOn");
         }
      }

      private function onEnterFrame(param1:Event) : void
      {
         if(this.disposed)
         {
            this.stopClock();
            return;
         }
         var now:int = getTimer();
         var elapsed:Number = this.lastTime > 0 ? now - this.lastTime : 0;
         this.lastTime = now;
         elapsed = CanvasChronomarkStyle.clamp(elapsed,0,250);
         this.updateAlert(elapsed);
         this.updateScanner(elapsed);
         this.updateDetection(elapsed);
         var sounds:Array = this.effects.updatePulse(elapsed);
         var index:int = 0;
         while(index < sounds.length)
         {
            this.playSound(String(sounds[index]));
            index++;
         }
         if(!this.needsClock())
         {
            this.stopClock();
         }
      }

      private function updateAlert(param1:Number) : void
      {
         if(this.activeAlert == null)
         {
            return;
         }
         this.alertElapsed += param1;
         var duration:Number = 0;
         if(this.alertPhase == "enter")
         {
            duration = this.activeAlert.kind == "personal" ? CanvasChronomarkStyle.PERSONAL_ENTER_MS : CanvasChronomarkStyle.ENVIRONMENT_ENTER_MS;
            this.view.setAlertAlpha(this.alertElapsed / duration);
            if(this.alertElapsed >= duration)
            {
               this.alertPhase = "dwell";
               this.alertElapsed = 0;
               this.view.setAlertAlpha(1);
            }
         }
         else if(this.alertPhase == "dwell")
         {
            if(this.alertElapsed >= Number(this.activeAlert.dwell))
            {
               this.alertPhase = "exit";
               this.alertElapsed = 0;
               if(this.activeAlert.kind == "personal")
               {
                  this.playSound("UIAfflictionPainWarningScreenOff");
               }
            }
         }
         else if(this.alertPhase == "exit")
         {
            duration = this.activeAlert.kind == "personal" ? CanvasChronomarkStyle.PERSONAL_EXIT_MS : CanvasChronomarkStyle.ENVIRONMENT_EXIT_MS;
            this.view.setAlertAlpha(1 - this.alertElapsed / duration);
            if(this.alertElapsed >= duration)
            {
               this.activeAlert = null;
               this.beginNextAlert();
            }
         }
      }

      private function updateScanner(param1:Number) : void
      {
         if(Math.abs(this.scannerTarget - this.scannerAlpha) < 0.001)
         {
            this.scannerAlpha = this.scannerTarget;
            if(this.scannerHoldRemaining > 0 && this.scannerTarget == 1)
            {
               this.scannerHoldRemaining = Math.max(0,this.scannerHoldRemaining - param1);
               if(this.scannerHoldRemaining == 0)
               {
                  this.scannerTarget = 0;
               }
            }
            return;
         }
         var duration:Number = this.scannerTarget > this.scannerAlpha ? CanvasChronomarkStyle.PLANET_ENTER_MS : CanvasChronomarkStyle.PLANET_EXIT_MS;
         var amount:Number = duration > 0 ? param1 / duration : 1;
         if(this.scannerTarget > this.scannerAlpha)
         {
            this.scannerAlpha = Math.min(this.scannerTarget,this.scannerAlpha + amount);
         }
         else
         {
            this.scannerAlpha = Math.max(this.scannerTarget,this.scannerAlpha - amount);
         }
         this.view.setScannerAlpha(this.scannerAlpha);
      }

      private function updateDetection(param1:Number) : void
      {
         if(Math.abs(this.detectionTarget - this.detectionAlpha) < 0.001)
         {
            this.detectionAlpha = this.detectionTarget;
            this.view.setDetection(this.detectionAlpha > 0,this.detectionAlpha);
            return;
         }
         var amount:Number = CanvasChronomarkStyle.FADE_IN_MS > 0 ? param1 / CanvasChronomarkStyle.FADE_IN_MS : 1;
         if(this.detectionTarget > this.detectionAlpha)
         {
            this.detectionAlpha = Math.min(this.detectionTarget,this.detectionAlpha + amount);
         }
         else
         {
            this.detectionAlpha = Math.max(this.detectionTarget,this.detectionAlpha - amount);
         }
         this.view.setDetection(true,this.detectionAlpha);
      }

      private function refreshClock() : void
      {
         if(this.disposed || this.clockRunning || !this.needsClock())
         {
            return;
         }
         this.clockRunning = true;
         this.lastTime = getTimer();
         this.clockSource.addEventListener(Event.ENTER_FRAME,this.onEnterFrame,false,0,true);
      }

      private function stopClock() : void
      {
         if(!this.clockRunning)
         {
            return;
         }
         this.clockRunning = false;
         this.lastTime = 0;
         if(this.clockSource != null)
         {
            this.clockSource.removeEventListener(Event.ENTER_FRAME,this.onEnterFrame);
         }
      }

      private function needsClock() : Boolean
      {
         return this.activeAlert != null || this.scannerHoldRemaining > 0 || Math.abs(this.scannerTarget - this.scannerAlpha) >= 0.001 || Math.abs(this.detectionTarget - this.detectionAlpha) >= 0.001 || this.effects.needsPulse();
      }

      private function playSound(param1:String) : void
      {
         if(param1 == "" || this.sound == null)
         {
            return;
         }
         try
         {
            this.sound(param1);
         }
         catch(soundError:*)
         {
         }
      }
   }
}
