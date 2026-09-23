package
{
   internal final class CanvasChronomarkData
   {
      private static const CHANNELS:Array = ["LocalEnvironmentData","LocalEnvData_Frequent","PlayerData","PlayerFrequentData","HudCompassData","PersonalEffectsData","PersonalAlertsData","EnvironmentEffectsData","EnvironmentAlertsData","HUDOpacityData"];

      private static const MAX_ALERTS:int = CanvasChronomarkStyle.ALERT_QUEUE_CAPACITY;

      private static const MAX_TEXT_CHARACTERS:int = 96;

      private var dataManager:Object;

      private var receiver:Function;

      private var diagnostic:Function;

      private var callbacks:Object;

      private var subscribed:Object;

      private var reported:Object;

      private var generation:uint = 0;

      private var disposed:Boolean = true;

      public function CanvasChronomarkData(param1:Object, param2:Function, param3:Function)
      {
         this.dataManager = param1;
         this.receiver = param2;
         this.diagnostic = param3;
         this.callbacks = {};
         this.subscribed = {};
         this.reported = {};
      }

      public function initialize() : Boolean
      {
         if(!this.disposed || this.dataManager == null || this.receiver == null || !("GetDataFromClient" in this.dataManager) || !("Subscribe" in this.dataManager) || !("Unsubscribe" in this.dataManager))
         {
            return false;
         }
         this.disposed = false;
         this.generation++;
         var currentGeneration:uint = this.generation;
         var channel:String = null;
         for each(channel in CHANNELS)
         {
            this.callbacks[channel] = this.createCallback(channel,currentGeneration);
            this.subscribed[channel] = false;
         }
         try
         {
            for each(channel in CHANNELS)
            {
               this.dataManager.GetDataFromClient(channel,true);
               this.subscribed[channel] = true;
               this.dataManager.Subscribe(channel,this.callbacks[channel]);
               if(this.disposed || this.generation != currentGeneration || this.callbacks[channel] == null)
               {
                  throw new Error("Chronomark subscription ownership changed");
               }
            }
         }
         catch(subscribeError:*)
         {
            this.report("subscribe","CHRONOMARK SUBSCRIBE FAILED");
            this.dispose();
            return false;
         }
         return true;
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         this.generation++;
         var channel:String = null;
         for each(channel in CHANNELS)
         {
            var callback:Function = this.callbacks[channel] as Function;
            var owned:Boolean = this.subscribed[channel] === true;
            this.subscribed[channel] = false;
            if(owned && callback != null && this.dataManager != null)
            {
               try
               {
                  this.dataManager.Unsubscribe(channel,callback);
               }
               catch(unsubscribeError:*)
               {
                  this.report("unsubscribe-" + channel,"CHRONOMARK UNSUBSCRIBE FAILED | " + channel);
               }
            }
         }
         this.callbacks = {};
      }

      private function createCallback(param1:String, param2:uint) : Function
      {
         var callback:Function = null;
         callback = function(param3:Object):void
         {
            if(disposed || generation != param2 || callbacks[param1] !== callback || subscribed[param1] !== true)
            {
               return;
            }
            receive(param1,param3);
         };
         return callback;
      }

      private function receive(param1:String, param2:Object) : void
      {
         try
         {
            var data:Object = this.unwrap(param2);
            var normalized:Object = this.normalize(param1,data);
            if(!this.disposed && normalized != null)
            {
               this.receiver(param1,normalized);
            }
         }
         catch(payloadError:*)
         {
            this.report("payload-" + param1,"CHRONOMARK PAYLOAD REJECTED | " + param1);
         }
      }

      private function normalize(param1:String, param2:Object) : Object
      {
         switch(param1)
         {
            case "LocalEnvironmentData":
               return this.normalizeLocalEnvironment(param2);
            case "LocalEnvData_Frequent":
               return {"localPlanetTime":this.numberValue(param2,"fLocalPlanetTime",0,0,1)};
            case "PlayerData":
               return {"inCombat":this.booleanValue(param2,"bIsInCombat",false)};
            case "PlayerFrequentData":
               return {
                  "maximum":this.numberValue(param2,"fMaxO2CO2",0,0,1000000000),
                  "oxygen":this.numberValue(param2,"fOxygen",0,0,1000000000),
                  "carbonDioxide":this.numberValue(param2,"fCarbonDioxide",0,0,1000000000),
                  "detectionLevel":this.integerValue(param2,"uDetectionLevel",CanvasChronomarkStyle.DETECTION_FULLY_HIDDEN,0,CanvasChronomarkStyle.DETECTION_FULLY_HIDDEN)
               };
            case "HudCompassData":
               return {
                  "direction":this.numberValue(param2,"fDirection",0,-1000000,1000000),
                  "markers":this.normalizeMarkers(this.member(param2,"aMarkers"),CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY),
                  "missionMarkers":this.normalizeMarkers(this.member(param2,"aMissionMarkers"),CanvasChronomarkStyle.MISSION_MARKER_CAPACITY),
                  "enemyMarkers":this.normalizeMarkers(this.member(param2,"aEnemyMarkers"),CanvasChronomarkStyle.ENEMY_MARKER_CAPACITY)
               };
            case "PersonalEffectsData":
               return {
                  "alertTimeMs":this.durationValue(param2,"uAlertTimeMS"),
                  "effects":this.normalizePersonalEffects(this.member(param2,"aPersonalEffects"))
               };
            case "PersonalAlertsData":
               return {"alerts":this.normalizeAlerts(this.member(param2,"aPersonalAlerts"),false)};
            case "EnvironmentEffectsData":
               return {
                  "alertTimeMs":this.durationValue(param2,"uAlertTimeMS"),
                  "pulseMinimumMs":this.numberValue(param2,"uEnvIconPulseMinMS",0,0,10000),
                  "pulseMaximumMs":this.numberValue(param2,"uEnvIconPulseMaxMS",0,0,10000),
                  "soakPercent":this.numberValue(param2,"fSoakDamagePct",0,0,1),
                  "pulseAtFullSoak":this.booleanValue(param2,"bShouldPlayAlertAtFullSoak",false),
                  "effects":this.normalizeEffects(this.member(param2,"aEnvironmentEffects"),CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY)
               };
            case "EnvironmentAlertsData":
               return {"alerts":this.normalizeAlerts(this.member(param2,"aEnvironmentAlerts"),true)};
            case "HUDOpacityData":
               return {"opacity":this.numberValue(param2,"fHUDOpacity",1,0,1)};
         }
         return null;
      }

      private function normalizeLocalEnvironment(param1:Object) : Object
      {
         return {
            "inSpaceship":this.booleanValue(param1,"bInSpaceship",false),
            "isLanded":this.booleanValue(param1,"bIsLanded",false),
            "shipInCruiseMode":this.booleanValue(param1,"bIsShipInCruiseMode",false),
            "cruiseDistance":this.numberValue(param1,"fCruiseDistance",0,0,1000000000000),
            "locationName":this.stringValue(param1,"sLocationName",MAX_TEXT_CHARACTERS),
            "language":this.stringValue(param1,"sLanguage",16),
            "bodyName":this.stringValue(param1,"sBodyName",MAX_TEXT_CHARACTERS),
            "bodyType":this.integerValue(param1,"uBodyType",0,0,255),
            "temperature":this.numberValue(param1,"fTemperature",0,-1000000,1000000),
            "oxygenPercent":this.numberValue(param1,"fOxygenPercent",0,0,100),
            "gravity":this.numberValue(param1,"fGravity",0,-1000000,1000000),
            "scanning":this.booleanValue(param1,"bIsScanning",false),
            "alertTimeMs":this.durationValue(param1,"uAlertTimeMS")
         };
      }

      private function normalizeMarkers(param1:Object, param2:int) : Array
      {
         var result:Array = [];
         var length:int = this.collectionLength(param1,param2);
         var index:int = 0;
         while(index < length)
         {
            var source:Object = param1[index];
            var handle:Number = this.numberValue(source,"uiHandle",0,0,4294967295);
            if(handle > 0)
            {
               result.push({
                  "handle":uint(handle),
                  "heading":this.numberValue(source,"fHeading",0,-1000000,1000000),
                  "isNear":this.booleanValue(source,"bIsNear",false),
                  "iconType":this.integerValue(source,"uiMarkerIconType",0,0,65535),
                  "relativeHeight":this.integerValue(source,"uiRelativeMarkerHeightType",0,0,3),
                  "mapMarkerType":this.integerValue(source,"uMapMarkerType",0,0,65535),
                  "mapMarkerCategory":this.integerValue(source,"uMapMarkerCategory",0,0,65535),
                  "locationMarkerState":this.integerValue(source,"uLocationMarkerState",0,0,2),
                  "mapMarkerSubCategoryType":this.integerValue(source,"uiMapMarkerSubCategoryType",0,0,3),
                  "scale":this.numberValue(source,"fDistanceScale",1,0.4,1.6),
                  "alpha":this.numberValue(source,"fDistanceAlpha",1,0.15,1)
               });
            }
            index++;
         }
         return result;
      }

      private function normalizeEffects(param1:Object, param2:int) : Array
      {
         var result:Array = [];
         var length:int = this.collectionLength(param1,param2);
         var index:int = 0;
         while(index < length)
         {
            var source:Object = param1[index];
            var icon:String = this.stringValue(source,"sEffectIcon",64);
            if(icon != "")
            {
               result.push({
                  "icon":icon,
                  "handle":uint(this.numberValue(source,"uiHandle",0,0,4294967295)),
                  "heading":this.numberValue(source,"fHeading",0,-1000000,1000000),
                  "isNear":this.booleanValue(source,"bIsNear",false),
                  "iconType":CanvasChronomarkStyle.MARKER_HAZARD,
                  "relativeHeight":this.integerValue(source,"uiRelativeMarkerHeightType",0,0,3),
                  "mapMarkerType":this.integerValue(source,"uMapMarkerType",0,0,65535),
                  "mapMarkerCategory":this.integerValue(source,"uMapMarkerCategory",0,0,65535),
                  "locationMarkerState":this.integerValue(source,"uLocationMarkerState",0,0,2),
                  "mapMarkerSubCategoryType":this.integerValue(source,"uiMapMarkerSubCategoryType",0,0,3),
                  "scale":this.numberValue(source,"fDistanceScale",1,0.4,1.6),
                  "alpha":this.numberValue(source,"fDistanceAlpha",1,0.15,1)
               });
            }
            index++;
         }
         return result;
      }

      private function normalizePersonalEffects(param1:Object) : Array
      {
         var personal:Array = [];
         var seen:Object = {};
         var length:int = this.collectionLength(param1,CanvasChronomarkStyle.PERSONAL_EFFECT_INGRESS_CAPACITY);
         var food:Object = null;
         var drink:Object = null;
         var foodPriority:int = -1;
         var drinkPriority:int = -1;
         var index:int = 0;
         while(index < length)
         {
            var source:Object = param1[index];
            var icon:String = this.stringValue(source,"sEffectIcon",64);
            var family:String = this.sustenanceFamily(icon);
            var priority:int = this.sustenancePriority(icon);
            if(family == "food" && priority > foodPriority)
            {
               food = this.normalizePersonalEffect(source,icon,true);
               foodPriority = priority;
            }
            else if(family == "drink" && priority > drinkPriority)
            {
               drink = this.normalizePersonalEffect(source,icon,true);
               drinkPriority = priority;
            }
            else if(family == "" && icon != "" && personal.length < CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY && !seen.hasOwnProperty("$" + icon))
            {
               seen["$" + icon] = true;
               personal.push(this.normalizePersonalEffect(source,icon,false));
            }
            index++;
         }
         if(food != null)
         {
            personal.push(food);
         }
         if(drink != null)
         {
            personal.push(drink);
         }
         return personal;
      }

      private function normalizePersonalEffect(param1:Object, param2:String, param3:Boolean) : Object
      {
         return {
            "icon":param2,
            "sustenance":param3,
            "handle":uint(this.numberValue(param1,"uiHandle",0,0,4294967295)),
            "heading":this.numberValue(param1,"fHeading",0,-1000000,1000000),
            "isNear":this.booleanValue(param1,"bIsNear",false),
            "scale":this.numberValue(param1,"fDistanceScale",1,0.4,1.6),
            "alpha":this.numberValue(param1,"fDistanceAlpha",1,0.15,1)
         };
      }

      private function sustenanceFamily(param1:String) : String
      {
         switch(param1)
         {
            case "Sustenance_Food_Positive_1":
            case "Sustenance_Food_Positive_2":
            case "Sustenance_Food_Positive_3":
            case "Sustenance_Food_Negative_1":
            case "Sustenance_Food_Negative_2":
               return "food";
            case "Sustenance_Drink_Positive_1":
            case "Sustenance_Drink_Positive_2":
            case "Sustenance_Drink_Positive_3":
            case "Sustenance_Drink_Negative_1":
            case "Sustenance_Drink_Negative_2":
               return "drink";
         }
         return "";
      }

      private function sustenancePriority(param1:String) : int
      {
         switch(param1)
         {
            case "Sustenance_Food_Positive_3":
            case "Sustenance_Drink_Positive_3":
               return 203;
            case "Sustenance_Food_Positive_2":
            case "Sustenance_Drink_Positive_2":
               return 202;
            case "Sustenance_Food_Positive_1":
            case "Sustenance_Drink_Positive_1":
               return 201;
            case "Sustenance_Food_Negative_2":
            case "Sustenance_Drink_Negative_2":
               return 102;
            case "Sustenance_Food_Negative_1":
            case "Sustenance_Drink_Negative_1":
               return 101;
         }
         return -1;
      }

      private function normalizeAlerts(param1:Object, param2:Boolean) : Array
      {
         var result:Array = [];
         var length:int = this.collectionLength(param1,MAX_ALERTS);
         var index:int = 0;
         while(index < length)
         {
            var source:Object = param1[index];
            var heading:String = this.stringValue(source,"sAlertText",MAX_TEXT_CHARACTERS);
            if(heading != "")
            {
               result.push({
                  "icon":this.stringValue(source,"sEffectIcon",64),
                  "heading":heading,
                  "subtext":this.stringValue(source,"sAlertSubText",MAX_TEXT_CHARACTERS),
                  "positive":param2 && this.booleanValue(source,"bIsPositive",false)
               });
            }
            index++;
         }
         return result;
      }

      private function unwrap(param1:Object) : Object
      {
         if(param1 == null || typeof param1 != "object")
         {
            throw new Error("invalid event");
         }
         var value:Object = "data" in param1 ? param1.data : param1;
         if(value == null || typeof value != "object")
         {
            throw new Error("invalid event data");
         }
         return value;
      }

      private function member(param1:Object, param2:String) : Object
      {
         return param1 != null && typeof param1 == "object" && param2 in param1 ? param1[param2] : null;
      }

      private function collectionLength(param1:Object, param2:int) : int
      {
         if(param1 == null || typeof param1 != "object" || !("length" in param1))
         {
            return 0;
         }
         var length:Number = Number(param1.length);
         if(!isFinite(length) || length < 0 || length != Math.floor(length))
         {
            return 0;
         }
         return int(Math.min(length,param2));
      }

      private function stringValue(param1:Object, param2:String, param3:int) : String
      {
         if(param1 == null || typeof param1 != "object" || !(param2 in param1) || typeof param1[param2] != "string")
         {
            return "";
         }
         var value:String = String(param1[param2]);
         return value.length <= param3 ? value : value.substr(0,param3);
      }

      private function booleanValue(param1:Object, param2:String, param3:Boolean) : Boolean
      {
         if(param1 == null || typeof param1 != "object" || !(param2 in param1))
         {
            return param3;
         }
         return param1[param2] === true;
      }

      private function integerValue(param1:Object, param2:String, param3:int, param4:int, param5:int) : int
      {
         return int(Math.round(this.numberValue(param1,param2,param3,param4,param5)));
      }

      private function durationValue(param1:Object, param2:String) : Number
      {
         return this.numberValue(param1,param2,CanvasChronomarkStyle.DEFAULT_DWELL_MS,CanvasChronomarkStyle.MIN_DWELL_MS,CanvasChronomarkStyle.MAX_DWELL_MS);
      }

      private function numberValue(param1:Object, param2:String, param3:Number, param4:Number, param5:Number) : Number
      {
         if(param1 == null || typeof param1 != "object" || !(param2 in param1))
         {
            return param3;
         }
         var value:Number = Number(param1[param2]);
         if(!isFinite(value))
         {
            return param3;
         }
         return CanvasChronomarkStyle.clamp(value,param4,param5);
      }

      private function report(param1:String, param2:String) : void
      {
         if(this.reported[param1] === true)
         {
            return;
         }
         this.reported[param1] = true;
         if(this.diagnostic != null)
         {
            try
            {
               this.diagnostic(param2);
            }
            catch(diagnosticError:*)
            {
            }
         }
      }
   }
}
