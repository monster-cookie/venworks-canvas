package
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasExample extends MovieClip
   {
      private static const TEXT_COLOR:uint = 14941695;

      private static const ACCENT_COLOR:uint = 3845628;

      private static const CASSIOPEIA_YEAR_DAYS:Number = 343;

      private static const CASSIOPEIA_ECCENTRICITY:Number = 0.032944;

      private static const CASSIOPEIA_AXIAL_TILT:Number = 0.5235988;

      private static const CASSIOPEIA_START_ANGLE:Number = 62 * Math.PI / 180;

      private static const CASSIOPEIA_PERIHELION_ANGLE:Number = 342 * Math.PI / 180;

      private static const PANEL_X:Number = 32;

      private static const PANEL_Y:Number = 28;

      private static const PANEL_WIDTH:Number = 460;

      private static const PANEL_HEIGHT:Number = 166;

      private var panel:Shape;

      private var clockFormat:TextFormat;

      private var universalTimeField:TextField;

      private var localTimeField:TextField;

      private var coordinatesField:TextField;

      private var timeSolarField:TextField;

      private var orbitalSolarField:TextField;

      private var inSpaceship:Boolean = false;

      private var localPlanetTime:Number = NaN;

      private var localPlanetHoursPerDay:Number = NaN;

      private var galacticStandardTime:Number = NaN;

      private var surfaceLatitude:Number = NaN;

      private var surfaceLongitude:Number = NaN;

      private var orbitalGameDays:Number = NaN;

      private var isCassiopeiaI:Boolean = false;

      private var orbitalSunrisePhase:Number = NaN;

      private var orbitalSunsetPhase:Number = NaN;

      private var orbitalSolarStatus:String = "";

      public function CanvasExample()
      {
         this.clockFormat = new TextFormat("$MAIN_Font_Bold",18,TEXT_COLOR,true);
         this.createClock();
         this.renderClock();
      }

      public function getCanvasRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/2",
            "consumerId":"a8098c1a-f86e-4b1e-9d7c-5a102bf38460",
            "assetNamespace":"venworks.canvas.example",
            "version":1,
            "minimumContractVersion":2,
            "maximumContractVersion":2,
            "uiChannels":["LocalEnvironmentData","LocalEnvData_Frequent"],
            "eventTopics":["venworks.canvas.example.location.changed"],
            "marker":"EXAMPLE"
         };
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
         if(param1 == "LocalEnvironmentData")
         {
            this.inSpaceship = this.booleanValue(param2,"bInSpaceship",false);
         }
         else if(param1 == "LocalEnvData_Frequent")
         {
            this.localPlanetTime = this.numberValue(param2,"fLocalPlanetTime",0,1);
            this.localPlanetHoursPerDay = this.numberValue(param2,"fLocalPlanetHoursPerDay",0,1000000);
            this.galacticStandardTime = this.numberValue(param2,"fGalacticStandardTime",0,24);
         }
         this.renderClock();
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         if(param1 == "venworks.canvas.example.location.changed")
         {
            var locationBody:String = param2 == null ? "" : param2.toUpperCase();
            this.surfaceLatitude = this.parseLocationCoordinate(param2,"LAT",90);
            this.surfaceLongitude = this.parseLocationCoordinate(param2,"LON",180);
            this.isCassiopeiaI = locationBody.indexOf("|PLANET=CASSIOPEIA_I|") >= 0 || locationBody.indexOf("LOCATION=[LOCATION <CASSIOPEIAIPLANETWORLDLANDINGOVERLAY") >= 0;
            this.orbitalGameDays = this.parseEventNumber(param2,"gt",0,100000000);
            this.updateOrbitalSolarPhases();
            this.renderClock();
         }
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(param1 == "ready")
         {
            this.renderClock();
         }
      }

      public function dispose() : void
      {
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
         this.panel = null;
         this.clockFormat = null;
         this.universalTimeField = null;
         this.localTimeField = null;
         this.coordinatesField = null;
         this.timeSolarField = null;
         this.orbitalSolarField = null;
      }

      private function createClock() : void
      {
         this.panel = new Shape();
         this.panel.graphics.beginFill(1315860,0.82);
         this.panel.graphics.lineStyle(1,ACCENT_COLOR,0.9);
         this.panel.graphics.drawRect(PANEL_X,PANEL_Y,PANEL_WIDTH,PANEL_HEIGHT);
         this.panel.graphics.endFill();
         addChild(this.panel);
         this.universalTimeField = this.createClockField(PANEL_Y + 9);
         this.localTimeField = this.createClockField(PANEL_Y + 38);
         this.coordinatesField = this.createClockField(PANEL_Y + 67);
         this.timeSolarField = this.createClockField(PANEL_Y + 96);
         this.orbitalSolarField = this.createClockField(PANEL_Y + 125);
      }

      private function createClockField(param1:Number) : TextField
      {
         var field:TextField = new TextField();
         field.x = PANEL_X + 14;
         field.y = param1;
         field.width = PANEL_WIDTH - 28;
         field.height = 27;
         field.embedFonts = true;
         field.defaultTextFormat = this.clockFormat;
         field.selectable = false;
         field.mouseEnabled = false;
         addChild(field);
         return field;
      }

      private function renderClock() : void
      {
         if(this.universalTimeField == null || this.localTimeField == null || this.coordinatesField == null || this.timeSolarField == null || this.orbitalSolarField == null)
         {
            return;
         }
         this.setClockText(this.universalTimeField,"UNIVERSAL TIME   " + this.formatClock(this.galacticStandardTime) + " UT");
         this.setClockText(this.coordinatesField,"LAT/LON          " + this.formatCoordinate(this.surfaceLatitude) + " / " + this.formatCoordinate(this.surfaceLongitude));
         if(this.inSpaceship || !isFinite(this.localPlanetTime) || !isFinite(this.localPlanetHoursPerDay) || this.localPlanetHoursPerDay <= 0)
         {
            this.setClockText(this.localTimeField,"LOCAL TIME       --:--");
            this.setClockText(this.timeSolarField,"TIME ONLY        UNAVAILABLE");
            this.setClockText(this.orbitalSolarField,"ORBIT EST        UNAVAILABLE");
         }
         else
         {
            this.setClockText(this.localTimeField,"LOCAL TIME       " + this.formatClock(this.localPlanetTime * 24));
            this.setClockText(this.timeSolarField,this.formatNextSolarTransition("TIME ONLY",0.25,0.75));
            this.setClockText(this.orbitalSolarField,this.formatOrbitalSolarTransition());
         }
      }

      private function setClockText(param1:TextField, param2:String) : void
      {
         if(param1.text != param2)
         {
            param1.text = param2;
            param1.setTextFormat(this.clockFormat);
         }
      }

      private function formatNextSolarTransition(param1:String, param2:Number, param3:Number) : String
      {
         var phase:Number = this.localPlanetTime;
         var daylight:Boolean = phase >= param2 && phase < param3;
         var target:Number = daylight ? param3 : param2;
         if(target <= phase)
         {
            target += 1;
         }
         var remainingMinutes:int = Math.max(0,Math.round((target - phase) * this.localPlanetHoursPerDay * 60));
         var hours:int = Math.floor(remainingMinutes / 60);
         var minutes:int = remainingMinutes % 60;
         return param1 + (daylight ? "  SUNSET IN " : "  SUNRISE IN ") + this.pad(hours) + "H " + this.pad(minutes) + "M";
      }

      private function formatOrbitalSolarTransition() : String
      {
         if(!this.hasSurfaceCoordinates())
         {
            return "ORBIT EST        LOCATION PENDING";
         }
         if(!this.isCassiopeiaI)
         {
            return "ORBIT EST        CASSIOPEIA I ONLY";
         }
         if(!isFinite(this.orbitalGameDays))
         {
            return "ORBIT EST        GAME TIME PENDING";
         }
         if(this.orbitalSolarStatus != "")
         {
            return "ORBIT EST        " + this.orbitalSolarStatus;
         }
         if(!isFinite(this.orbitalSunrisePhase) || !isFinite(this.orbitalSunsetPhase))
         {
            return "ORBIT EST        UNAVAILABLE";
         }
         return this.formatNextSolarTransition("ORBIT EST",this.orbitalSunrisePhase,this.orbitalSunsetPhase);
      }

      private function updateOrbitalSolarPhases() : void
      {
         this.orbitalSunrisePhase = NaN;
         this.orbitalSunsetPhase = NaN;
         this.orbitalSolarStatus = "";
         if(!this.hasSurfaceCoordinates() || !this.isCassiopeiaI || !isFinite(this.orbitalGameDays))
         {
            return;
         }
         // Start and perihelion angles are treated as an epoch and orbit orientation;
         // the game's solstice alignment is not exposed, so this remains an estimate.
         var meanAnomaly:Number = 2 * Math.PI * (this.orbitalGameDays / CASSIOPEIA_YEAR_DAYS % 1) + CASSIOPEIA_START_ANGLE;
         var eccentricAnomaly:Number = meanAnomaly;
         for(var iteration:int = 0; iteration < 6; iteration++)
         {
            eccentricAnomaly -= (eccentricAnomaly - CASSIOPEIA_ECCENTRICITY * Math.sin(eccentricAnomaly) - meanAnomaly) / (1 - CASSIOPEIA_ECCENTRICITY * Math.cos(eccentricAnomaly));
         }
         var trueAnomaly:Number = Math.atan2(Math.sqrt(1 - CASSIOPEIA_ECCENTRICITY * CASSIOPEIA_ECCENTRICITY) * Math.sin(eccentricAnomaly),Math.cos(eccentricAnomaly) - CASSIOPEIA_ECCENTRICITY);
         var solarDeclination:Number = Math.asin(Math.sin(CASSIOPEIA_AXIAL_TILT) * Math.sin(trueAnomaly + CASSIOPEIA_PERIHELION_ANGLE));
         var latitudeRadians:Number = this.surfaceLatitude * Math.PI / 180;
         var horizonCosine:Number = -Math.tan(latitudeRadians) * Math.tan(solarDeclination);
         if(horizonCosine >= 1)
         {
            this.orbitalSolarStatus = "POLAR NIGHT";
            return;
         }
         if(horizonCosine <= -1)
         {
            this.orbitalSolarStatus = "POLAR DAY";
            return;
         }
         if(!isFinite(horizonCosine))
         {
            return;
         }
         var halfDayPhase:Number = Math.acos(horizonCosine) / (2 * Math.PI);
         this.orbitalSunrisePhase = 0.5 - halfDayPhase;
         this.orbitalSunsetPhase = 0.5 + halfDayPhase;
      }

      private function formatCoordinate(param1:Number) : String
      {
         return isFinite(param1) ? param1.toFixed(4) : "--";
      }

      private function formatClock(param1:Number) : String
      {
         if(!isFinite(param1))
         {
            return "--:--";
         }
         var normalized:Number = param1 % 24;
         if(normalized < 0)
         {
            normalized += 24;
         }
         var totalMinutes:int = Math.floor(normalized * 60) % 1440;
         return this.pad(Math.floor(totalMinutes / 60)) + ":" + this.pad(totalMinutes % 60);
      }

      private function pad(param1:int) : String
      {
         return param1 < 10 ? "0" + param1 : String(param1);
      }

      private function hasSurfaceCoordinates() : Boolean
      {
         return isFinite(this.surfaceLatitude) && isFinite(this.surfaceLongitude);
      }

      private function parseLocationCoordinate(param1:String, param2:String, param3:Number) : Number
      {
         if(param1 == null || param1 == "")
         {
            return NaN;
         }
         var source:String = param1.toUpperCase();
         var positiveToken:String = param2 + "POS";
         var negativeToken:String = param2 + "NEG";
         var tokenIndex:int = source.indexOf(positiveToken);
         var sign:Number = 1;
         var tokenLength:int = positiveToken.length;
         if(tokenIndex < 0)
         {
            tokenIndex = source.indexOf(negativeToken);
            sign = -1;
            tokenLength = negativeToken.length;
         }
         if(tokenIndex < 0)
         {
            return NaN;
         }
         var index:int = tokenIndex + tokenLength;
         var digits:String = "";
         while(index < source.length)
         {
            var code:int = source.charCodeAt(index);
            if(code < 48 || code > 57)
            {
               break;
            }
            digits += source.charAt(index);
            index++;
         }
         if(digits.length == 0)
         {
            return NaN;
         }
         var coordinate:Number = Number(digits) / 100000;
         if(!isFinite(coordinate) || coordinate > param3)
         {
            return NaN;
         }
         return sign * coordinate;
      }

      private function parseEventNumber(param1:String, param2:String, param3:Number, param4:Number) : Number
      {
         if(param1 == null)
         {
            return NaN;
         }
         var source:String = param1.toUpperCase();
         var token:String = "|" + param2.toUpperCase() + "=";
         var start:int = source.indexOf(token);
         if(start < 0)
         {
            return NaN;
         }
         start += token.length;
         var end:int = source.indexOf("|",start);
         if(end < 0)
         {
            end = source.length;
         }
         if(end == start)
         {
            return NaN;
         }
         var value:Number = Number(source.substring(start,end));
         return isFinite(value) && value >= param3 && value <= param4 ? value : NaN;
      }

      private function numberValue(param1:Object, param2:String, param3:Number, param4:Number) : Number
      {
         try
         {
            if(param1 != null && param2 in param1)
            {
               var value:Number = Number(param1[param2]);
               if(isFinite(value) && value >= param3 && value <= param4)
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

      private function booleanValue(param1:Object, param2:String, param3:Boolean) : Boolean
      {
         try
         {
            if(param1 != null && param2 in param1)
            {
               return param1[param2] === true;
            }
         }
         catch(valueError:*)
         {
         }
         return param3;
      }
   }
}
