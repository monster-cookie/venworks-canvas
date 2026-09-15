package
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.filters.DropShadowFilter;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.text.TextFormatAlign;

   internal final class CanvasChronomarkView extends Sprite
   {
      private var normalFaceLayer:Sprite;

      private var informationLayer:Sprite;

      private var normalInteriorLayer:Sprite;

      private var scannerLayer:Sprite;

      private var dayCycleShape:Shape;

      private var oxygenShape:Shape;

      private var oxygenTrackShape:Shape;

      private var carbonDioxideShape:Shape;

      private var localPlanetTimeFrame:int = -1;

      private var oxygenFrame:int = -1;

      private var carbonDioxideFrame:int = -1;

      private var pointerShape:Shape;

      private var detectionShape:Shape;

      private var bodyTypeField:TextField;

      private var bodyNameField:TextField;

      private var temperatureField:TextField;

      private var oxygenField:TextField;

      private var gravityField:TextField;

      private var statusField:TextField;

      private var locationFields:Array;

      private var alertLayer:Sprite;

      private var alertBackdrop:Shape;

      private var alertIcon:Shape;

      private var alertHeading:TextField;

      private var alertSubtext:TextField;

      public function CanvasChronomarkView()
      {
         super();
         mouseEnabled = false;
         mouseChildren = false;
         this.locationFields = [];
         this.createFace();
         this.createInformation();
         this.createAlert();
         this.setLocalEnvironment({});
         this.setOxygen(1,0);
         this.setLocalPlanetTime(0);
         this.setDirection(0);
         this.setDetection(false,0);
         this.setScannerAlpha(0);
         this.clearAlert();
      }

      public function setLocalEnvironment(param1:Object) : void
      {
         var inFlight:Boolean = param1 != null && param1.inSpaceship === true && param1.isLanded !== true;
         this.dayCycleShape.visible = !inFlight;
         var bodyName:String = param1 != null && param1.bodyName != null ? String(param1.bodyName) : "";
         var bodyType:String = inFlight ? "$SHIP" : CanvasChronomarkStyle.bodyTypeLabel(param1 != null ? uint(param1.bodyType) : 0);
         this.bodyNameField.text = bodyName;
         this.bodyTypeField.text = this.bodyNameField.numLines == 1 ? bodyType : "";
         this.temperatureField.text = this.formatInteger(param1 != null ? Number(param1.temperature) : 0) + "°";
         this.oxygenField.text = this.formatInteger(param1 != null ? Number(param1.oxygenPercent) : 0) + "%";
         this.gravityField.text = this.formatDecimal(param1 != null ? Number(param1.gravity) : 0,2);
         if(inFlight)
         {
            this.statusField.text = param1.shipInCruiseMode === true ? "$AUTOPILOT " + this.formatDistance(Number(param1.cruiseDistance)) : "$OFF PLANET";
         }
         else
         {
            this.statusField.text = "";
         }
         this.setLocation(param1 != null ? String(param1.locationName) : "",param1 != null ? String(param1.language) : "");
      }

      public function setLocalPlanetTime(param1:Number) : void
      {
         var frame:int = int(Math.round(CanvasChronomarkStyle.clamp(param1,0,1) * 47));
         if(this.localPlanetTimeFrame == frame)
         {
            return;
         }
         this.localPlanetTimeFrame = frame;
         var value:Number = frame / 47;
         var phase:Number = value * Math.PI * 2;
         var firstHalf:Boolean = phase <= Math.PI;
         var litSide:Number = firstHalf ? 1 : -1;
         var terminatorScale:Number = firstHalf ? Math.cos(phase) : -Math.cos(phase);
         var radius:Number = CanvasChronomarkStyle.DAY_PLANET_RADIUS;
         var centerX:Number = CanvasChronomarkStyle.FACE_CENTER_X;
         var centerY:Number = CanvasChronomarkStyle.FACE_CENTER_Y;
         var segments:int = 24;
         var index:int = 0;
         var y:Number = 0;
         var extent:Number = 0;
         this.dayCycleShape.graphics.clear();
         this.dayCycleShape.graphics.beginFill(1054752,0.94);
         this.dayCycleShape.graphics.drawCircle(centerX,centerY,radius);
         this.dayCycleShape.graphics.endFill();
         this.dayCycleShape.graphics.beginFill(CanvasChronomarkStyle.TEXT_COLOR,0.72);
         while(index <= segments)
         {
            y = -radius + radius * 2 * index / segments;
            extent = Math.sqrt(Math.max(0,radius * radius - y * y));
            if(index == 0)
            {
               this.dayCycleShape.graphics.moveTo(centerX + terminatorScale * extent,centerY + y);
            }
            else
            {
               this.dayCycleShape.graphics.lineTo(centerX + terminatorScale * extent,centerY + y);
            }
            index++;
         }
         index = segments;
         while(index >= 0)
         {
            y = -radius + radius * 2 * index / segments;
            extent = Math.sqrt(Math.max(0,radius * radius - y * y));
            this.dayCycleShape.graphics.lineTo(centerX + litSide * extent,centerY + y);
            index--;
         }
         this.dayCycleShape.graphics.endFill();
         this.dayCycleShape.graphics.lineStyle(1.5,CanvasChronomarkStyle.MUTED_TEXT_COLOR,0.85,true);
         this.dayCycleShape.graphics.drawCircle(centerX,centerY,radius);
         this.dayCycleShape.graphics.lineStyle(1,CanvasChronomarkStyle.MUTED_TEXT_COLOR,0.35,true);
         this.dayCycleShape.graphics.moveTo(centerX - radius * 0.72,centerY + 8);
         this.dayCycleShape.graphics.curveTo(centerX,centerY + 20,centerX + radius * 0.72,centerY + 8);
      }

      public function setOxygen(param1:Number, param2:Number) : void
      {
         var nextOxygenFrame:int = int(Math.round(CanvasChronomarkStyle.clamp(param1,0,1) * 59));
         var nextCarbonDioxideFrame:int = int(Math.round(CanvasChronomarkStyle.clamp(param2,0,1) * 59));
         if(this.oxygenFrame != nextOxygenFrame)
         {
            this.oxygenFrame = nextOxygenFrame;
            var oxygen:Number = nextOxygenFrame / 59;
            this.oxygenShape.graphics.clear();
            this.oxygenShape.graphics.lineStyle(8,CanvasChronomarkStyle.OXYGEN_COLOR,0.95,true);
            this.drawArc(this.oxygenShape,CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,CanvasChronomarkStyle.OXYGEN_METER_RADIUS,CanvasChronomarkStyle.OXYGEN_METER_START_ANGLE,CanvasChronomarkStyle.OXYGEN_METER_SWEEP,oxygen);
            this.oxygenShape.graphics.lineStyle(2,CanvasChronomarkStyle.TEXT_COLOR,0.92,true);
            this.drawArc(this.oxygenShape,CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,CanvasChronomarkStyle.OXYGEN_METER_RADIUS,CanvasChronomarkStyle.OXYGEN_METER_START_ANGLE,CanvasChronomarkStyle.OXYGEN_METER_SWEEP,oxygen);
         }
         if(this.carbonDioxideFrame != nextCarbonDioxideFrame)
         {
            this.carbonDioxideFrame = nextCarbonDioxideFrame;
            var carbonDioxide:Number = nextCarbonDioxideFrame / 59;
            this.carbonDioxideShape.graphics.clear();
            this.carbonDioxideShape.graphics.lineStyle(7,CanvasChronomarkStyle.CARBON_DIOXIDE_COLOR,0.98,true);
            this.drawArc(this.carbonDioxideShape,CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,CanvasChronomarkStyle.OXYGEN_METER_RADIUS,CanvasChronomarkStyle.OXYGEN_METER_START_ANGLE + CanvasChronomarkStyle.OXYGEN_METER_SWEEP,-CanvasChronomarkStyle.OXYGEN_METER_SWEEP,carbonDioxide);
         }
      }

      public function setDirection(param1:Number) : void
      {
         this.pointerShape.rotation = 360 - param1 * 180 / Math.PI;
      }

      public function setDetection(param1:Boolean, param2:Number) : void
      {
         this.detectionShape.visible = param1;
         this.detectionShape.alpha = CanvasChronomarkStyle.clamp(param2,0,1);
      }

      public function setScannerAlpha(param1:Number) : void
      {
         var value:Number = CanvasChronomarkStyle.clamp(param1,0,1);
         this.scannerLayer.alpha = value;
         this.scannerLayer.visible = value > 0;
         this.normalFaceLayer.alpha = 1 - value;
         this.normalFaceLayer.visible = value < 1;
         this.normalInteriorLayer.alpha = 1 - value;
         this.normalInteriorLayer.visible = value < 1;
      }

      public function addNormalContent(param1:Sprite) : void
      {
         if(param1 != null)
         {
            this.normalInteriorLayer.addChild(param1);
         }
      }

      public function showAlert(param1:String, param2:String, param3:String, param4:String, param5:Boolean, param6:Number) : void
      {
         var personal:Boolean = param1 == "personal";
         this.alertLayer.visible = true;
         this.alertLayer.alpha = CanvasChronomarkStyle.clamp(param6,0,1);
         this.alertBackdrop.graphics.clear();
         this.alertBackdrop.graphics.beginFill(personal ? 15522019 : 0,personal ? 0.94 : 0.82);
         this.alertBackdrop.graphics.drawCircle(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,82);
         this.alertBackdrop.graphics.endFill();
         if(personal)
         {
            this.alertBackdrop.graphics.lineStyle(2,0,0.12,true);
            var stripe:int = -3;
            while(stripe <= 3)
            {
               this.alertBackdrop.graphics.moveTo(53,CanvasChronomarkStyle.FACE_CENTER_Y + stripe * 13 + 18);
               this.alertBackdrop.graphics.lineTo(168,CanvasChronomarkStyle.FACE_CENTER_Y + stripe * 13 - 18);
               stripe++;
            }
         }
         this.alertBackdrop.graphics.lineStyle(2,personal ? 0 : param5 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,0.88,true);
         this.alertBackdrop.graphics.drawCircle(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,82);
         this.alertIcon.visible = param2 != "";
         if(this.alertIcon.visible)
         {
            CanvasChronomarkEffects.drawEffect(this.alertIcon,personal ? 0 : param5 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,param2);
         }
         else
         {
            this.alertIcon.graphics.clear();
         }
         this.alertHeading.defaultTextFormat = new TextFormat("$MAIN_Font_Bold",personal ? 18 : 26,personal ? 0 : param5 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,true,null,null,null,null,TextFormatAlign.CENTER);
         this.alertHeading.text = param3;
         this.alertHeading.setTextFormat(this.alertHeading.defaultTextFormat);
         this.alertSubtext.defaultTextFormat = new TextFormat("$MAIN_Font_Bold",16,personal ? 0 : param5 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,false,null,null,null,null,TextFormatAlign.CENTER);
         this.alertSubtext.text = personal ? "" : param4;
         this.alertSubtext.setTextFormat(this.alertSubtext.defaultTextFormat);
      }

      public function setAlertAlpha(param1:Number) : void
      {
         this.alertLayer.alpha = CanvasChronomarkStyle.clamp(param1,0,1);
      }

      public function clearAlert() : void
      {
         this.alertLayer.visible = false;
         this.alertLayer.alpha = 0;
         this.alertHeading.text = "";
         this.alertSubtext.text = "";
         this.alertBackdrop.graphics.clear();
         this.alertIcon.graphics.clear();
         this.alertIcon.visible = false;
      }

      public function takeAlertLayer() : Sprite
      {
         if(this.alertLayer.parent != null)
         {
            this.alertLayer.parent.removeChild(this.alertLayer);
         }
         return this.alertLayer;
      }

      public function dispose() : void
      {
         this.locationFields = [];
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
      }

      private function createFace() : void
      {
         var face:Shape = new Shape();
         face.graphics.lineStyle(3,CanvasChronomarkStyle.RIM_COLOR,1,true);
         face.graphics.beginFill(CanvasChronomarkStyle.FACE_COLOR,0.94);
         face.graphics.drawCircle(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,CanvasChronomarkStyle.FACE_RADIUS);
         face.graphics.endFill();
         face.filters = [new DropShadowFilter(4,90,0,0.75,10,10,1,1,false,false,false)];
         addChild(face);

         this.normalFaceLayer = new Sprite();
         addChild(this.normalFaceLayer);

         var innerRim:Shape = new Shape();
         innerRim.graphics.lineStyle(1,CanvasChronomarkStyle.MUTED_TEXT_COLOR,0.5,true);
         innerRim.graphics.drawCircle(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,99);
         this.normalFaceLayer.addChild(innerRim);

         var compassTicks:Shape = new Shape();
         var index:int = 0;
         while(index < 24)
         {
            var radians:Number = (index * 15 - 90) * Math.PI / 180;
            var innerRadius:Number = index % 6 == 0 ? 87 : index % 2 == 0 ? 90 : 92;
            compassTicks.graphics.lineStyle(index % 6 == 0 ? 2 : 1,CanvasChronomarkStyle.MUTED_TEXT_COLOR,index % 6 == 0 ? 0.8 : 0.45,true);
            compassTicks.graphics.moveTo(CanvasChronomarkStyle.FACE_CENTER_X + Math.cos(radians) * innerRadius,CanvasChronomarkStyle.FACE_CENTER_Y + Math.sin(radians) * innerRadius);
            compassTicks.graphics.lineTo(CanvasChronomarkStyle.FACE_CENTER_X + Math.cos(radians) * 96,CanvasChronomarkStyle.FACE_CENTER_Y + Math.sin(radians) * 96);
            index++;
         }
         this.normalFaceLayer.addChild(compassTicks);

         this.oxygenTrackShape = new Shape();
         this.oxygenTrackShape.graphics.lineStyle(10,CanvasChronomarkStyle.RIM_COLOR,0.55,true);
         this.drawArc(this.oxygenTrackShape,CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,CanvasChronomarkStyle.OXYGEN_METER_RADIUS,CanvasChronomarkStyle.OXYGEN_METER_START_ANGLE,CanvasChronomarkStyle.OXYGEN_METER_SWEEP,1);
         this.oxygenShape = new Shape();
         this.carbonDioxideShape = new Shape();
         this.normalFaceLayer.addChild(this.oxygenTrackShape);
         this.normalFaceLayer.addChild(this.oxygenShape);
         this.normalFaceLayer.addChild(this.carbonDioxideShape);
      }

      private function createInformation() : void
      {
         this.informationLayer = new Sprite();
         addChild(this.informationLayer);

         this.normalInteriorLayer = new Sprite();
         this.informationLayer.addChild(this.normalInteriorLayer);

         this.scannerLayer = new Sprite();
         this.informationLayer.addChild(this.scannerLayer);

         this.dayCycleShape = new Shape();
         this.normalInteriorLayer.addChild(this.dayCycleShape);

         this.pointerShape = new Shape();
         this.pointerShape.x = 111;
         this.pointerShape.y = 111;
         this.pointerShape.graphics.beginFill(CanvasChronomarkStyle.TEXT_COLOR,0.92);
         this.pointerShape.graphics.moveTo(0,-104);
         this.pointerShape.graphics.lineTo(-4,-94);
         this.pointerShape.graphics.lineTo(4,-94);
         this.pointerShape.graphics.lineTo(0,-104);
         this.pointerShape.graphics.endFill();
         this.normalInteriorLayer.addChild(this.pointerShape);

         this.bodyTypeField = this.createText(38,75,145,21,16,CanvasChronomarkStyle.MUTED_TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.bodyNameField = this.createText(20,94,181.5,25,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.bodyNameField.multiline = true;
         this.bodyNameField.wordWrap = true;
         this.statusField = this.createText(35,158,151,18,12,CanvasChronomarkStyle.MUTED_TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.scannerLayer.addChild(this.bodyTypeField);
         this.scannerLayer.addChild(this.bodyNameField);
         this.normalInteriorLayer.addChild(this.statusField);

         this.temperatureField = this.createText(31,130,47,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.oxygenField = this.createText(87,130,47,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.gravityField = this.createText(143,130,47,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.scannerLayer.addChild(this.temperatureField);
         this.scannerLayer.addChild(this.oxygenField);
         this.scannerLayer.addChild(this.gravityField);
         this.createMetric(31,153,"$TEMP");
         this.createMetric(87,153,"$O2");
         this.createMetric(143,153,"$GRAV");

         var index:int = 0;
         while(index < CanvasChronomarkStyle.LOCATION_CHARACTER_CAPACITY)
         {
            var locationField:TextField = this.createText(-9,-8,18,18,13,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
            locationField.autoSize = TextFieldAutoSize.CENTER;
            this.locationFields.push(locationField);
            this.normalInteriorLayer.addChild(locationField);
            index++;
         }

         this.detectionShape = new Shape();
         this.detectionShape.graphics.lineStyle(3,CanvasChronomarkStyle.ALERT_COLOR,1,true);
         this.detectionShape.graphics.moveTo(92,45);
         this.detectionShape.graphics.lineTo(110.5,36);
         this.detectionShape.graphics.lineTo(129,45);
         this.normalInteriorLayer.addChild(this.detectionShape);
      }

      private function createMetric(param1:Number, param2:Number, param3:String) : void
      {
         var label:TextField = this.createText(param1,param2,51,16,12,CanvasChronomarkStyle.MUTED_TEXT_COLOR,true,TextFormatAlign.CENTER);
         label.text = param3;
         this.scannerLayer.addChild(label);
      }

      private function createAlert() : void
      {
         this.alertLayer = new Sprite();
         this.alertBackdrop = new Shape();
         this.alertIcon = new Shape();
         this.alertIcon.x = CanvasChronomarkStyle.FACE_CENTER_X;
         this.alertIcon.y = 72;
         this.alertIcon.scaleX = this.alertIcon.scaleY = 1.25;
         this.alertHeading = this.createText(25,85,171,53,26,CanvasChronomarkStyle.ALERT_COLOR,true,TextFormatAlign.CENTER);
         this.alertSubtext = this.createText(30,132,161,40,16,CanvasChronomarkStyle.ALERT_COLOR,false,TextFormatAlign.CENTER);
         this.alertHeading.multiline = true;
         this.alertHeading.wordWrap = true;
         this.alertSubtext.multiline = true;
         this.alertSubtext.wordWrap = true;
         this.alertLayer.addChild(this.alertBackdrop);
         this.alertLayer.addChild(this.alertIcon);
         this.alertLayer.addChild(this.alertHeading);
         this.alertLayer.addChild(this.alertSubtext);
         addChild(this.alertLayer);
      }

      private function setLocation(param1:String, param2:String) : void
      {
         var language:String = param2.toLowerCase();
         var visible:Boolean = language != "ja" && language != "zhhans";
         var length:int = Math.min(param1.length,CanvasChronomarkStyle.LOCATION_CHARACTER_CAPACITY);
         var index:int = 0;
         var angle:Number = 0;
         var radians:Number = 0;
         while(index < this.locationFields.length)
         {
            var field:TextField = this.locationFields[index] as TextField;
            field.visible = visible && index < length;
            field.text = index < length ? param1.charAt(index) : "";
            if(field.visible)
            {
               angle = 90 - (index - (length - 1) / 2) * 9;
               radians = angle * Math.PI / 180;
               field.x = CanvasChronomarkStyle.FACE_CENTER_X + Math.cos(radians) * CanvasChronomarkStyle.LOCATION_TEXT_RADIUS - field.width / 2;
               field.y = CanvasChronomarkStyle.FACE_CENTER_Y + Math.sin(radians) * CanvasChronomarkStyle.LOCATION_TEXT_RADIUS - field.height / 2;
               field.rotation = angle - 90;
            }
            index++;
         }
      }

      private function createText(param1:Number, param2:Number, param3:Number, param4:Number, param5:Number, param6:uint, param7:Boolean, param8:String) : TextField
      {
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",param5,param6,param7,null,null,null,null,param8);
         var field:TextField = new TextField();
         field.x = param1;
         field.y = param2;
         field.width = param3;
         field.height = param4;
         field.embedFonts = true;
         field.defaultTextFormat = format;
         field.setTextFormat(format);
         field.selectable = false;
         field.mouseEnabled = false;
         return field;
      }

      private function drawArc(param1:Shape, param2:Number, param3:Number, param4:Number, param5:Number, param6:Number, param7:Number) : void
      {
         var sweep:Number = param6 * CanvasChronomarkStyle.clamp(param7,0,1);
         if(Math.abs(sweep) <= 0)
         {
            return;
         }
         var steps:int = Math.max(1,Math.ceil(Math.abs(sweep) / 6));
         var index:int = 0;
         var radians:Number = param5 * Math.PI / 180;
         param1.graphics.moveTo(param2 + Math.cos(radians) * param4,param3 + Math.sin(radians) * param4);
         while(index < steps)
         {
            index++;
            radians = (param5 + sweep * index / steps) * Math.PI / 180;
            param1.graphics.lineTo(param2 + Math.cos(radians) * param4,param3 + Math.sin(radians) * param4);
         }
      }

      private function formatInteger(param1:Number) : String
      {
         return isFinite(param1) ? Math.round(param1).toString() : "0";
      }

      private function formatDecimal(param1:Number, param2:int) : String
      {
         if(!isFinite(param1))
         {
            return "0.00";
         }
         return param1.toFixed(param2);
      }

      private function formatDistance(param1:Number) : String
      {
         if(!isFinite(param1) || param1 <= 0)
         {
            return "";
         }
         return Math.round(param1).toString() + "m";
      }
   }
}
