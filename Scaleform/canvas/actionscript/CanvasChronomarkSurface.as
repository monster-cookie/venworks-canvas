package
{
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.geom.Matrix3D;
   import flash.geom.Point;
   import flash.geom.Rectangle;

   internal final class CanvasChronomarkSurface extends MovieClip
   {
      private var view:CanvasChronomarkView;

      private var markers:CanvasChronomarkMarkers;

      private var effects:CanvasChronomarkEffects;

      private var alertLayer:Sprite;

      private var animation:CanvasChronomarkAnimation;

      private var data:CanvasChronomarkData;

      private var sound:Function;

      private var diagnostic:Function;

      private var displayMode:String = "normal";

      private var disposed:Boolean = false;

      private var initialized:Boolean = false;

      private var ownerAppliesOpacity:Boolean = true;

      private var localEnvironment:Object;

      private var playerFrequent:Object;

      private var inCombat:Boolean = false;

      private var personalAlertTimeMs:Number = CanvasChronomarkStyle.DEFAULT_DWELL_MS;

      private var environmentAlertTimeMs:Number = CanvasChronomarkStyle.DEFAULT_DWELL_MS;

      private var previousOxygen:Number = -1;

      private var previousCarbonDioxide:Number = -1;

      private var hasLocalEnvironment:Boolean = false;

      private var hasScannerState:Boolean = false;

      private var scanning:Boolean = false;

      private var hasDetectionState:Boolean = false;

      public function CanvasChronomarkSurface()
      {
         super();
         mouseEnabled = false;
         mouseChildren = false;
         this.view = new CanvasChronomarkView();
         this.markers = new CanvasChronomarkMarkers();
         this.effects = new CanvasChronomarkEffects();
         this.alertLayer = this.view.takeAlertLayer();
         addChild(this.view);
         addChild(this.markers);
         addChild(this.effects);
         addChild(this.alertLayer);
      }

      public function initialize(param1:Object, param2:String, param3:Function, param4:Function, param5:Object) : Boolean
      {
         if(this.disposed || this.initialized || (param2 != "normal" && param2 != "large"))
         {
            return false;
         }
         this.displayMode = param2;
         this.sound = param3;
         this.diagnostic = param4;
         this.animation = new CanvasChronomarkAnimation(this,this.view,this.effects,this.sound);
         this.updateLayout(param5);
         this.data = new CanvasChronomarkData(param1,this.onData,this.diagnostic);
         if(!this.data.initialize())
         {
            this.dispose();
            return false;
         }
         this.initialized = true;
         return true;
      }

      public function updateLayout(param1:Object) : void
      {
         if(this.disposed)
         {
            return;
         }
         var profile:Object = CanvasChronomarkStyle.profile(this.displayMode);
         var values:Array = profile.matrix as Array;
         var vector:Vector.<Number> = new Vector.<Number>(16,true);
         var index:int = 0;
         while(index < vector.length)
         {
            vector[index] = Number(values[index]);
            index++;
         }
         transform.matrix3D = new Matrix3D(vector);
         if(param1 == null || typeof param1 != "object")
         {
            return;
         }
         this.ownerAppliesOpacity = !("ownerAppliesOpacity" in param1) || param1.ownerAppliesOpacity === true;
         var visibleX:Number = this.layoutNumber(param1,"visibleX",0);
         var visibleY:Number = this.layoutNumber(param1,"visibleY",0);
         var visibleWidth:Number = this.layoutNumber(param1,"visibleWidth",1920);
         var visibleHeight:Number = this.layoutNumber(param1,"visibleHeight",1080);
         var safeX:Number = this.layoutNumber(param1,"safeX",0);
         var safeY:Number = this.layoutNumber(param1,"safeY",0);
         if(this.parent != null && visibleWidth > 0 && visibleHeight > 0)
         {
            var bounds:Rectangle = this.getMeasuredFaceBounds();
            this.x += visibleX + safeX - bounds.x;
            this.y += visibleY + visibleHeight - safeY - (bounds.y + bounds.height);
         }
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         this.initialized = false;
         if(this.data != null)
         {
            this.data.dispose();
         }
         if(this.animation != null)
         {
            this.animation.dispose();
         }
         this.data = null;
         this.animation = null;
         if(this.effects != null)
         {
            this.effects.dispose();
         }
         if(this.markers != null)
         {
            this.markers.dispose();
         }
         if(this.view != null)
         {
            this.view.dispose();
         }
         this.effects = null;
         this.markers = null;
         this.view = null;
         this.alertLayer = null;
         this.sound = null;
         this.diagnostic = null;
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
      }

      private function onData(param1:String, param2:Object) : void
      {
         if(this.disposed)
         {
            return;
         }
         switch(param1)
         {
            case "LocalEnvironmentData":
               this.handleLocalEnvironment(param2);
               break;
            case "LocalEnvData_Frequent":
               this.view.setLocalPlanetTime(Number(param2.localPlanetTime));
               break;
            case "PlayerData":
               this.inCombat = param2.inCombat === true;
               this.updateDetection();
               break;
            case "PlayerFrequentData":
               this.playerFrequent = param2;
               this.updateOxygen();
               this.updateDetection();
               break;
            case "HudCompassData":
               this.view.setDirection(Number(param2.direction));
               this.markers.setCompass(param2);
               break;
            case "PersonalEffectsData":
               this.personalAlertTimeMs = Number(param2.alertTimeMs);
               this.effects.setPersonalEffects(param2.effects as Array);
               break;
            case "PersonalAlertsData":
               this.animation.enqueuePersonalAlerts(param2.alerts as Array,this.personalAlertTimeMs);
               break;
            case "EnvironmentEffectsData":
               this.environmentAlertTimeMs = Number(param2.alertTimeMs);
               this.effects.setEnvironmentEffects(param2.effects as Array,Number(param2.pulseMinimumMs),Number(param2.pulseMaximumMs),Number(param2.soakPercent),param2.pulseAtFullSoak === true);
               this.markers.setHazards(param2.effects as Array);
               this.animation.refreshPulseClock();
               break;
            case "EnvironmentAlertsData":
               this.animation.enqueueEnvironmentAlerts(param2.alerts as Array,this.environmentAlertTimeMs);
               break;
            case "HudModeData":
               visible = param2.visible === true;
               break;
            case "HUDOpacityData":
               if(!this.ownerAppliesOpacity)
               {
                  alpha = Number(param2.opacity);
               }
               break;
         }
      }

      private function handleLocalEnvironment(param1:Object) : void
      {
         var initial:Boolean = !this.hasLocalEnvironment;
         var leftSpaceship:Boolean = !initial && this.localEnvironment != null && this.localEnvironment.inSpaceship === true && param1.inSpaceship !== true;
         var nextScanning:Boolean = param1.scanning === true;
         var scannerChanged:Boolean = this.hasScannerState && this.scanning != nextScanning;
         this.hasLocalEnvironment = true;
         this.localEnvironment = param1;
         this.view.setLocalEnvironment(param1);
         if(!this.hasScannerState || scannerChanged)
         {
            this.animation.setScannerState(nextScanning,!this.hasScannerState);
         }
         this.hasScannerState = true;
         this.scanning = nextScanning;
         if(leftSpaceship && !nextScanning && !scannerChanged)
         {
            this.animation.showPlanetInformation(Number(param1.alertTimeMs));
         }
         this.updateOxygen();
      }

      private function updateOxygen() : void
      {
         if(this.localEnvironment == null || this.playerFrequent == null)
         {
            return;
         }
         var maximum:Number = Number(this.playerFrequent.maximum);
         var oxygen:Number = maximum > 0 ? Number(this.playerFrequent.oxygen) / maximum : 1;
         var carbonDioxide:Number = maximum > 0 ? Number(this.playerFrequent.carbonDioxide) / maximum : 1;
         oxygen = CanvasChronomarkStyle.clamp(oxygen,0,1);
         carbonDioxide = CanvasChronomarkStyle.clamp(carbonDioxide,0,1);
         this.view.setOxygen(oxygen,carbonDioxide);
         if(this.previousOxygen >= 0 && this.previousCarbonDioxide >= 0)
         {
            if(this.previousOxygen > CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE && oxygen <= CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE)
            {
               this.playSound("VOC_Player_O2_Min");
            }
            if(this.previousCarbonDioxide > CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE && carbonDioxide <= CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE)
            {
               this.playSound("VOC_Player_CO2_Cleared");
            }
            if(this.previousCarbonDioxide < 1 - CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE && carbonDioxide >= 1 - CanvasChronomarkStyle.OXYGEN_THRESHOLD_TOLERANCE)
            {
               this.playSound("VOC_Player_CO2_Max");
            }
         }
         this.previousOxygen = oxygen;
         this.previousCarbonDioxide = carbonDioxide;
      }

      private function updateDetection() : void
      {
         if(this.playerFrequent == null)
         {
            return;
         }
         var show:Boolean = this.inCombat && uint(this.playerFrequent.detectionLevel) < CanvasChronomarkStyle.DETECTION_FULLY_HIDDEN;
         this.animation.setDetectionState(show,!this.hasDetectionState);
         this.hasDetectionState = true;
      }

      private function playSound(param1:String) : void
      {
         if(this.sound == null)
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

      private function layoutNumber(param1:Object, param2:String, param3:Number) : Number
      {
         if(!(param2 in param1))
         {
            return param3;
         }
         var value:Number = Number(param1[param2]);
         return isFinite(value) ? value : param3;
      }

      private function getMeasuredFaceBounds() : Rectangle
      {
         var corners:Array = [new Point(0,0),new Point(CanvasChronomarkStyle.FACE_SIZE,0),new Point(0,CanvasChronomarkStyle.FACE_SIZE),new Point(CanvasChronomarkStyle.FACE_SIZE,CanvasChronomarkStyle.FACE_SIZE)];
         var minimumX:Number = Number.POSITIVE_INFINITY;
         var minimumY:Number = Number.POSITIVE_INFINITY;
         var maximumX:Number = Number.NEGATIVE_INFINITY;
         var maximumY:Number = Number.NEGATIVE_INFINITY;
         var index:int = 0;
         while(index < corners.length)
         {
            var point:Point = this.parent.globalToLocal(localToGlobal(corners[index] as Point));
            minimumX = Math.min(minimumX,point.x);
            minimumY = Math.min(minimumY,point.y);
            maximumX = Math.max(maximumX,point.x);
            maximumY = Math.max(maximumY,point.y);
            index++;
         }
         return new Rectangle(minimumX,minimumY,maximumX - minimumX,maximumY - minimumY);
      }
   }
}
