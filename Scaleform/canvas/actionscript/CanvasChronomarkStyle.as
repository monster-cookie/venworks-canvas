package
{
   internal final class CanvasChronomarkStyle
   {
      public static const FACE_SIZE:Number = 221;

      public static const FACE_CENTER_X:Number = 110.5;

      public static const FACE_CENTER_Y:Number = 110.5;

      public static const FACE_RADIUS:Number = 110.5;

      public static const FACE_COLOR:uint = 0;

      public static const RIM_COLOR:uint = 7566195;

      public static const TEXT_COLOR:uint = 16777215;

      public static const MUTED_TEXT_COLOR:uint = 12040119;

      public static const ALERT_COLOR:uint = 12794665;

      public static const OXYGEN_COLOR:uint = 52479;

      public static const CARBON_DIOXIDE_COLOR:uint = 13382451;

      public static const OXYGEN_METER_RADIUS:Number = 90.8;

      public static const OXYGEN_METER_START_ANGLE:Number = 18;

      public static const OXYGEN_METER_SWEEP:Number = 144;

      public static const DAY_PLANET_RADIUS:Number = 45;

      public static const LOCATION_TEXT_RADIUS:Number = 55;

      public static const GENERAL_MARKER_CAPACITY:int = 48;

      public static const MISSION_MARKER_CAPACITY:int = 16;

      public static const ENEMY_MARKER_CAPACITY:int = 16;

      public static const PERSONAL_EFFECT_CAPACITY:int = 5;

      public static const SUSTENANCE_EFFECT_CAPACITY:int = 2;

      public static const PERSONAL_EFFECT_INGRESS_CAPACITY:int = 48;

      public static const ENVIRONMENT_EFFECT_CAPACITY:int = 4;

      public static const ALERT_QUEUE_CAPACITY:int = 16;

      public static const LOCATION_CHARACTER_CAPACITY:int = 21;

      public static const DEFAULT_DWELL_MS:Number = 3000;

      public static const MIN_DWELL_MS:Number = 250;

      public static const MAX_DWELL_MS:Number = 15000;

      public static const FADE_IN_MS:Number = 333.333333;

      public static const FADE_OUT_MS:Number = 333.333333;

      public static const ENVIRONMENT_ENTER_MS:Number = 1233.333333;

      public static const ENVIRONMENT_EXIT_MS:Number = 566.666667;

      public static const PERSONAL_ENTER_MS:Number = 1233.333333;

      public static const PERSONAL_EXIT_MS:Number = 566.666667;

      public static const PLANET_ENTER_MS:Number = 1533.333333;

      public static const PLANET_EXIT_MS:Number = 600;

      public static const DETECTION_FULLY_HIDDEN:uint = 100;

      public static const OXYGEN_THRESHOLD_TOLERANCE:Number = 0.001;

      public static const LOCATION_MARKER_TYPE:int = 7;

      public static const MARKER_QUEST:int = 1;

      public static const MARKER_QUEST_DOOR:int = 2;

      public static const MARKER_QUEST_OFFPLANET:int = 3;

      public static const MARKER_PLAYER_SET:int = 4;

      public static const MARKER_ENEMY:int = 5;

      public static const MARKER_ENEMY_TARGETED:int = 6;

      public static const MARKER_LOCATION:int = 7;

      public static const MARKER_COMPANION:int = 8;

      public static const MARKER_RECON:int = 9;

      public static const MARKER_SHIP:int = 10;

      public static const MARKER_OUTPOST:int = 11;

      public static const MARKER_HAZARD:int = 12;

      public static const MARKER_POSITION:int = 13;

      public static const MARKER_VEHICLE:int = 14;

      public static function profile(param1:String) : Object
      {
         if(param1 == "large")
         {
            return {
               "matrix":[1.134053,-0.073151,-0.160659,0,-0.040079,1.131038,0.203869,0,0.127329,-0.171576,0.976908,0,41.096493,795.546082,-4.567053,1],
               "displayMode":"large"
            };
         }
         return {
            "matrix":[1.065422,-0.06871,-0.150934,0,-0.037639,1.062183,0.191458,0,0.127329,-0.171576,0.976908,0,41.719982,807.84552,-4.454321,1],
            "displayMode":"normal"
         };
      }

      public static function bodyTypeLabel(param1:uint) : String
      {
         switch(param1)
         {
            case 1:
               return "$Star";
            case 2:
               return "$Planet";
            case 3:
               return "$Moon";
            case 4:
               return "$Satellite";
            case 5:
               return "$Asteroid Belt";
            case 6:
               return "$Station";
         }
         return "$Unknown Type";
      }

      public static function screenSoundForEffect(param1:String) : String
      {
         switch(param1)
         {
            case "HazardEffect_Radiation":
               return "UIHazardRadiationWarningScreen";
            case "HazardEffect_Thermal":
               return "UIHazardThermalWarningScreen";
            case "HazardEffect_Airborne":
               return "UIHazardAirborneWarningScreen";
            case "HazardEffect_Corrosive":
               return "UIHazardCorrosiveWarningScreen";
            case "HazardEffect_RestoreSoak":
               return "UIHazardSuitSoakRestore_WarningScreen";
            case "PersonalEffect_CardioRespiratoryCirculatory":
            case "PersonalEffect_SkeletalMuscular":
            case "PersonalEffect_NervousSystem":
            case "PersonalEffect_DigestiveImmune":
            case "PersonalEffect_Misc":
               return "UIHazardDamagePermanent";
         }
         return "";
      }

      public static function pulseSoundForEffect(param1:String) : String
      {
         switch(param1)
         {
            case "HazardEffect_Radiation":
               return "UIHazardRadiationWarningIcon";
            case "HazardEffect_Thermal":
               return "UIHazardThermalWarningIcon";
            case "HazardEffect_Airborne":
               return "UIHazardAirborneWarningIcon";
            case "HazardEffect_Corrosive":
               return "UIHazardCorrosiveWarningIcon";
            case "HazardEffect_RestoreSoak":
               return "UIHazardSuitSoakRestore_Icon";
         }
         return "";
      }

      public static function clamp(param1:Number, param2:Number, param3:Number) : Number
      {
         if(param1 < param2)
         {
            return param2;
         }
         if(param1 > param3)
         {
            return param3;
         }
         return param1;
      }
   }
}
