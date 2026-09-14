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
      private var informationLayer:Sprite;

      private var scannerLayer:Sprite;

      private var dayCycleShape:Shape;

      private var oxygenShape:Shape;

      private var carbonDioxideShape:Shape;

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
         var value:Number = CanvasChronomarkStyle.clamp(param1,0,1);
         value = Math.round(value * 47) / 47;
         var angle:Number = -180 + value * 180;
         var radians:Number = angle * Math.PI / 180;
         this.dayCycleShape.graphics.clear();
         this.dayCycleShape.graphics.lineStyle(2,CanvasChronomarkStyle.MUTED_TEXT_COLOR,0.65,true);
         this.drawArc(this.dayCycleShape,CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,93,180,180,1);
         this.dayCycleShape.graphics.lineStyle(2,CanvasChronomarkStyle.TEXT_COLOR,0.9,true);
         this.dayCycleShape.graphics.moveTo(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y);
         this.dayCycleShape.graphics.lineTo(CanvasChronomarkStyle.FACE_CENTER_X + Math.cos(radians) * 91,CanvasChronomarkStyle.FACE_CENTER_Y + Math.sin(radians) * 91);
      }

      public function setOxygen(param1:Number, param2:Number) : void
      {
         var oxygen:Number = CanvasChronomarkStyle.clamp(param1,0,1);
         var carbonDioxide:Number = CanvasChronomarkStyle.clamp(param2,0,1);
         oxygen = Math.round(oxygen * 59) / 59;
         carbonDioxide = Math.round(carbonDioxide * 59) / 59;
         this.oxygenShape.graphics.clear();
         this.oxygenShape.graphics.lineStyle(7,CanvasChronomarkStyle.OXYGEN_COLOR,0.95,true);
         this.drawArc(this.oxygenShape,21.7,89.85,17,-80,160,oxygen);
         this.carbonDioxideShape.graphics.clear();
         this.carbonDioxideShape.graphics.lineStyle(4,CanvasChronomarkStyle.CARBON_DIOXIDE_COLOR,0.95,true);
         this.drawArc(this.carbonDioxideShape,16.1,88.3,11,-80,160,carbonDioxide);
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
         this.scannerLayer.alpha = CanvasChronomarkStyle.clamp(param1,0,1);
      }

      public function showAlert(param1:String, param2:String, param3:String, param4:Boolean, param5:Number) : void
      {
         var personal:Boolean = param1 == "personal";
         this.alertLayer.visible = true;
         this.alertLayer.alpha = CanvasChronomarkStyle.clamp(param5,0,1);
         this.alertBackdrop.graphics.clear();
         if(personal)
         {
            this.alertBackdrop.graphics.beginFill(15522019,0.94);
            this.alertBackdrop.graphics.drawRoundRect(28,69,165,83,8,8);
            this.alertBackdrop.graphics.endFill();
         }
         this.alertHeading.defaultTextFormat = new TextFormat("$MAIN_Font_Bold",personal ? 18 : 26,personal ? 0 : param4 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,true,null,null,null,null,TextFormatAlign.CENTER);
         this.alertHeading.text = param2;
         this.alertHeading.setTextFormat(this.alertHeading.defaultTextFormat);
         this.alertSubtext.defaultTextFormat = new TextFormat("$MAIN_Font_Bold",16,personal ? 0 : param4 ? 7454875 : CanvasChronomarkStyle.ALERT_COLOR,false,null,null,null,null,TextFormatAlign.CENTER);
         this.alertSubtext.text = personal ? "" : param3;
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

         var innerRim:Shape = new Shape();
         innerRim.graphics.lineStyle(1,CanvasChronomarkStyle.MUTED_TEXT_COLOR,0.5,true);
         innerRim.graphics.drawCircle(CanvasChronomarkStyle.FACE_CENTER_X,CanvasChronomarkStyle.FACE_CENTER_Y,99);
         addChild(innerRim);

         this.oxygenShape = new Shape();
         this.carbonDioxideShape = new Shape();
         addChild(this.oxygenShape);
         addChild(this.carbonDioxideShape);
      }

      private function createInformation() : void
      {
         this.informationLayer = new Sprite();
         addChild(this.informationLayer);

         this.scannerLayer = new Sprite();
         this.informationLayer.addChild(this.scannerLayer);

         this.dayCycleShape = new Shape();
         this.informationLayer.addChild(this.dayCycleShape);

         this.pointerShape = new Shape();
         this.pointerShape.x = 111;
         this.pointerShape.y = 111;
         this.pointerShape.graphics.beginFill(CanvasChronomarkStyle.TEXT_COLOR,0.92);
         this.pointerShape.graphics.moveTo(0,-104);
         this.pointerShape.graphics.lineTo(-4,-94);
         this.pointerShape.graphics.lineTo(4,-94);
         this.pointerShape.graphics.lineTo(0,-104);
         this.pointerShape.graphics.endFill();
         this.informationLayer.addChild(this.pointerShape);

         this.bodyTypeField = this.createText(38,75,145,21,16,CanvasChronomarkStyle.MUTED_TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.bodyNameField = this.createText(20,94,181.5,25,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.bodyNameField.multiline = true;
         this.bodyNameField.wordWrap = true;
         this.statusField = this.createText(35,117,151,18,12,CanvasChronomarkStyle.MUTED_TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.scannerLayer.addChild(this.bodyTypeField);
         this.scannerLayer.addChild(this.bodyNameField);
         this.informationLayer.addChild(this.statusField);

         this.createMetric(55,133.75,"$TEMP");
         this.temperatureField = this.createText(54,148,51.4,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.createMetric(88,133.75,"$O2");
         this.oxygenField = this.createText(87,148,51.9,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.createMetric(125,133.75,"$GRAV");
         this.gravityField = this.createText(124,148,51.4,24,18,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
         this.scannerLayer.addChild(this.temperatureField);
         this.scannerLayer.addChild(this.oxygenField);
         this.scannerLayer.addChild(this.gravityField);

         var index:int = 0;
         while(index < CanvasChronomarkStyle.LOCATION_CHARACTER_CAPACITY)
         {
            var locationField:TextField = this.createText(-9,-8,18,18,13,CanvasChronomarkStyle.TEXT_COLOR,true,TextFormatAlign.CENTER);
            locationField.autoSize = TextFieldAutoSize.CENTER;
            this.locationFields.push(locationField);
            this.informationLayer.addChild(locationField);
            index++;
         }

         this.detectionShape = new Shape();
         this.detectionShape.graphics.lineStyle(3,CanvasChronomarkStyle.ALERT_COLOR,1,true);
         this.detectionShape.graphics.moveTo(92,45);
         this.detectionShape.graphics.lineTo(110.5,36);
         this.detectionShape.graphics.lineTo(129,45);
         this.informationLayer.addChild(this.detectionShape);
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
         this.alertHeading = this.createText(25,82,171,58,26,CanvasChronomarkStyle.ALERT_COLOR,true,TextFormatAlign.CENTER);
         this.alertSubtext = this.createText(30,132,161,40,16,CanvasChronomarkStyle.ALERT_COLOR,false,TextFormatAlign.CENTER);
         this.alertHeading.multiline = true;
         this.alertHeading.wordWrap = true;
         this.alertSubtext.multiline = true;
         this.alertSubtext.wordWrap = true;
         this.alertLayer.addChild(this.alertBackdrop);
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
               angle = 90 + (index - (length - 1) / 2) * 9;
               radians = angle * Math.PI / 180;
               field.x = CanvasChronomarkStyle.FACE_CENTER_X + Math.cos(radians) * 87;
               field.y = CanvasChronomarkStyle.FACE_CENTER_Y + Math.sin(radians) * 87;
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
         if(sweep <= 0)
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
