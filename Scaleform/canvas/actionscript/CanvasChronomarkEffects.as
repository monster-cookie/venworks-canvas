package
{
   import flash.display.Shape;
   import flash.display.Sprite;

   internal final class CanvasChronomarkEffects extends Sprite
   {
      private var personalPool:Array;

      private var sustenancePool:Array;

      private var environmentPool:Array;

      private var activeEnvironmentIcons:Array;

      private var pulseMinimumMs:Number = 0;

      private var pulseMaximumMs:Number = 0;

      private var pulseSpeedPercent:Number = 0;

      private var pulseAtFullSoak:Boolean = false;

      private var pulseProgress:Number = 0;

      private var pulseIncreasing:Boolean = true;

      public function CanvasChronomarkEffects()
      {
         super();
         mouseEnabled = false;
         mouseChildren = false;
         this.personalPool = this.createPool(CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY,72,74.5);
         this.sustenancePool = this.createPool(CanvasChronomarkStyle.SUSTENANCE_EFFECT_CAPACITY,88.5,98.5,24);
         this.environmentPool = this.createPool(CanvasChronomarkStyle.ENVIRONMENT_EFFECT_CAPACITY,155,83.5);
         this.activeEnvironmentIcons = [];
      }

      public function setPersonalEffects(param1:Array) : void
      {
         var personal:Array = [];
         var sustenance:Array = [];
         var index:int = 0;
         while(param1 != null && index < param1.length && (personal.length < CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY || sustenance.length < CanvasChronomarkStyle.SUSTENANCE_EFFECT_CAPACITY))
         {
            var entry:Object = param1[index];
            if(entry != null)
            {
               if(entry.sustenance === true && sustenance.length < CanvasChronomarkStyle.SUSTENANCE_EFFECT_CAPACITY)
               {
                  sustenance.push(entry);
               }
               else if(entry.sustenance !== true && personal.length < CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY)
               {
                  personal.push(entry);
               }
            }
            index++;
         }
         this.renderPool(this.personalPool,this.uniqueIcons(personal,CanvasChronomarkStyle.PERSONAL_EFFECT_CAPACITY),1863319);
         this.renderPool(this.sustenancePool,this.uniqueIcons(sustenance,CanvasChronomarkStyle.SUSTENANCE_EFFECT_CAPACITY),CanvasChronomarkStyle.OXYGEN_COLOR);
      }

      public function setEnvironmentEffects(param1:Array, param2:Number, param3:Number, param4:Number, param5:Boolean) : void
      {
         this.activeEnvironmentIcons = this.uniqueIcons(param1,CanvasChronomarkStyle.ENVIRONMENT_EFFECT_CAPACITY);
         this.renderPool(this.environmentPool,this.activeEnvironmentIcons,CanvasChronomarkStyle.ALERT_COLOR);
         this.pulseMinimumMs = CanvasChronomarkStyle.clamp(param2,100,5000);
         this.pulseMaximumMs = CanvasChronomarkStyle.clamp(param3,this.pulseMinimumMs,10000);
         this.pulseSpeedPercent = CanvasChronomarkStyle.clamp(param4,0,1);
         this.pulseAtFullSoak = param5;
         if(!this.needsPulse())
         {
            this.pulseProgress = 0;
            this.pulseIncreasing = true;
            this.setEnvironmentAlpha(1);
         }
      }

      public function needsPulse() : Boolean
      {
         return this.activeEnvironmentIcons.length > 0 && this.pulseSpeedPercent < 1 && (this.pulseSpeedPercent > 0 || this.pulseAtFullSoak);
      }

      public static function iconStyle(param1:String) : String
      {
         switch(param1)
         {
            case "HazardEffect_Radiation":
               return "radiation";
            case "HazardEffect_Thermal":
               return "thermal";
            case "HazardEffect_Airborne":
               return "airborne";
            case "HazardEffect_Corrosive":
               return "corrosive";
            case "HazardEffect_RestoreSoak":
               return "restore";
            case "PersonalEffect_CardioRespiratoryCirculatory":
               return "cardio";
            case "PersonalEffect_SkeletalMuscular":
               return "skeletal";
            case "PersonalEffect_NervousSystem":
               return "nervous";
            case "PersonalEffect_DigestiveImmune":
               return "digestive";
            case "PersonalEffect_Misc":
               return "misc";
            case "Sustenance_Food_Positive_1":
            case "Sustenance_Food_Positive_2":
            case "Sustenance_Food_Positive_3":
               return "food-positive";
            case "Sustenance_Food_Negative_1":
            case "Sustenance_Food_Negative_2":
               return "food-negative";
            case "Sustenance_Drink_Positive_1":
            case "Sustenance_Drink_Positive_2":
            case "Sustenance_Drink_Positive_3":
               return "drink-positive";
            case "Sustenance_Drink_Negative_1":
            case "Sustenance_Drink_Negative_2":
               return "drink-negative";
         }
         return "unknown";
      }

      public function updatePulse(param1:Number) : Array
      {
         var sounds:Array = [];
         if(!this.needsPulse())
         {
            return sounds;
         }
         var duration:Number = this.pulseMinimumMs + (this.pulseMaximumMs - this.pulseMinimumMs) * this.pulseSpeedPercent;
         duration = CanvasChronomarkStyle.clamp(duration,100,10000);
         var amount:Number = CanvasChronomarkStyle.clamp(param1,0,250) / duration;
         if(this.pulseIncreasing)
         {
            this.pulseProgress += amount;
            if(this.pulseProgress >= 1)
            {
               this.pulseProgress = 1;
               this.pulseIncreasing = false;
               var index:int = 0;
               while(index < this.activeEnvironmentIcons.length)
               {
                  var sound:String = CanvasChronomarkStyle.pulseSoundForEffect(String(this.activeEnvironmentIcons[index]));
                  if(sound != "" && sounds.indexOf(sound) < 0)
                  {
                     sounds.push(sound);
                  }
                  index++;
               }
            }
         }
         else
         {
            this.pulseProgress -= amount;
            if(this.pulseProgress <= 0)
            {
               this.pulseProgress = 0;
               this.pulseIncreasing = true;
            }
         }
         this.setEnvironmentAlpha(this.pulseProgress);
         return sounds;
      }

      public function dispose() : void
      {
         this.personalPool = [];
         this.sustenancePool = [];
         this.environmentPool = [];
         this.activeEnvironmentIcons = [];
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
      }

      private function uniqueIcons(param1:Array, param2:int) : Array
      {
         var result:Array = [];
         var seen:Object = {};
         var index:int = 0;
         while(param1 != null && index < param1.length && result.length < param2)
         {
            var entry:Object = param1[index];
            var icon:String = entry != null && entry.icon != null ? String(entry.icon) : "";
            if(icon != "" && !seen.hasOwnProperty("$" + icon))
            {
               seen["$" + icon] = true;
               result.push(icon);
            }
            index++;
         }
         return result;
      }

      private function renderPool(param1:Array, param2:Array, param3:uint) : void
      {
         var index:int = 0;
         while(index < param1.length)
         {
            var display:Sprite = param1[index] as Sprite;
            display.visible = index < param2.length;
            if(display.visible)
            {
               drawEffect(display.getChildAt(0) as Shape,param3,String(param2[index]));
            }
            index++;
         }
      }

      public static function drawEffect(param1:Shape, param2:uint, param3:String) : void
      {
         var shape:Shape = param1;
         var style:String = iconStyle(param3);
         shape.graphics.clear();
         if(style == "food-positive" || style == "food-negative" || style == "drink-positive" || style == "drink-negative")
         {
            drawSustenanceEffect(shape,param3);
            return;
         }
         shape.graphics.lineStyle(1,param2,1,true);
         if(style == "radiation")
         {
            shape.graphics.drawCircle(0,0,1.5);
            shape.graphics.moveTo(-2,-2);
            shape.graphics.lineTo(-5,-6);
            shape.graphics.lineTo(2,-6);
            shape.graphics.lineTo(1,-2);
            shape.graphics.moveTo(2,1);
            shape.graphics.lineTo(6,4);
            shape.graphics.lineTo(1,7);
            shape.graphics.lineTo(0,2);
            shape.graphics.moveTo(-2,1);
            shape.graphics.lineTo(-6,4);
            shape.graphics.lineTo(-1,7);
            shape.graphics.lineTo(0,2);
         }
         else if(style == "thermal")
         {
            shape.graphics.drawCircle(0,4,3);
            shape.graphics.moveTo(0,4);
            shape.graphics.lineTo(0,-6);
            shape.graphics.moveTo(-2,-6);
            shape.graphics.lineTo(2,-6);
         }
         else if(style == "airborne")
         {
            drawWave(shape,-4);
            drawWave(shape,0);
            drawWave(shape,4);
         }
         else if(style == "corrosive")
         {
            shape.graphics.moveTo(-6,5);
            shape.graphics.lineTo(6,5);
            shape.graphics.moveTo(-6,-5);
            shape.graphics.lineTo(-1,-2);
            shape.graphics.moveTo(1,-5);
            shape.graphics.lineTo(6,-2);
            shape.graphics.drawCircle(-1,1,1);
            shape.graphics.drawCircle(5,1,1);
         }
         else if(style == "restore")
         {
            shape.graphics.moveTo(0,-7);
            shape.graphics.lineTo(6,-4);
            shape.graphics.lineTo(5,3);
            shape.graphics.lineTo(0,7);
            shape.graphics.lineTo(-5,3);
            shape.graphics.lineTo(-6,-4);
            shape.graphics.lineTo(0,-7);
            shape.graphics.moveTo(-3,0);
            shape.graphics.lineTo(3,0);
            shape.graphics.moveTo(0,-3);
            shape.graphics.lineTo(0,3);
         }
         else if(style == "cardio")
         {
            shape.graphics.moveTo(0,6);
            shape.graphics.lineTo(-6,0);
            shape.graphics.curveTo(-7,-5,-3,-6);
            shape.graphics.curveTo(0,-6,0,-3);
            shape.graphics.curveTo(0,-6,3,-6);
            shape.graphics.curveTo(7,-5,6,0);
            shape.graphics.lineTo(0,6);
         }
         else if(style == "skeletal")
         {
            shape.graphics.moveTo(-4,5);
            shape.graphics.lineTo(4,-5);
            shape.graphics.drawCircle(-5,6,2);
            shape.graphics.drawCircle(5,-6,2);
         }
         else if(style == "nervous")
         {
            shape.graphics.moveTo(2,-7);
            shape.graphics.lineTo(-3,0);
            shape.graphics.lineTo(1,0);
            shape.graphics.lineTo(-2,7);
            shape.graphics.lineTo(5,-2);
            shape.graphics.lineTo(1,-2);
            shape.graphics.lineTo(2,-7);
         }
         else if(style == "digestive")
         {
            shape.graphics.drawCircle(0,0,6);
            shape.graphics.moveTo(-3,-4);
            shape.graphics.curveTo(4,-2,-2,1);
            shape.graphics.curveTo(-5,4,3,5);
         }
         else if(style == "misc")
         {
            shape.graphics.drawCircle(0,0,6);
            shape.graphics.moveTo(-3,0);
            shape.graphics.lineTo(3,0);
            shape.graphics.moveTo(0,-3);
            shape.graphics.lineTo(0,3);
         }
         else
         {
            shape.graphics.drawCircle(0,0,5);
            shape.graphics.drawCircle(0,0,1);
         }
      }

      private static function drawSustenanceEffect(param1:Shape, param2:String) : void
      {
         var food:Boolean = param2.indexOf("Sustenance_Food_") == 0;
         var positive:Boolean = param2.indexOf("_Positive_") >= 0;
         var tier:int = int(param2.charAt(param2.length - 1));
         var color:uint = positive ? CanvasChronomarkStyle.SUSTENANCE_POSITIVE_COLOR : CanvasChronomarkStyle.SUSTENANCE_NEGATIVE_COLOR;
         var symbolOffset:Number = positive ? 0 : food ? -4.3 : -4.5;
         param1.graphics.lineStyle();
         param1.graphics.beginFill(color,1);
         if(positive)
         {
            param1.graphics.moveTo(-0.65,-10.3);
            param1.graphics.lineTo(7.15,-4.15);
            param1.graphics.curveTo(10.4,-0.95,10.4,3.6);
            param1.graphics.curveTo(10.4,8.25,7.15,11.5);
            param1.graphics.curveTo(3.9,14.75,-0.65,14.75);
            param1.graphics.curveTo(-5.3,14.75,-8.5,11.5);
            param1.graphics.curveTo(-11.8,8.25,-11.8,3.6);
            param1.graphics.curveTo(-11.8,-0.95,-8.5,-4.15);
            param1.graphics.lineTo(-0.65,-10.3);
         }
         else
         {
            var bodyOffset:Number = food ? 0 : -0.8;
            param1.graphics.moveTo(-8.55,7.4 + bodyOffset);
            param1.graphics.curveTo(-11.8,4.1 + bodyOffset,-11.8,-0.45 + bodyOffset);
            param1.graphics.curveTo(-11.8,-5.1 + bodyOffset,-8.55,-8.3 + bodyOffset);
            param1.graphics.curveTo(-5.3,-11.6 + bodyOffset,-0.7,-11.6 + bodyOffset);
            param1.graphics.curveTo(3.85,-11.6 + bodyOffset,7.15,-8.3 + bodyOffset);
            param1.graphics.curveTo(10.35,-5.1 + bodyOffset,10.35,-0.45 + bodyOffset);
            param1.graphics.curveTo(10.35,4.1 + bodyOffset,7.15,7.4 + bodyOffset);
            param1.graphics.lineTo(6.1,8.35 + bodyOffset);
            param1.graphics.lineTo(-0.7,13.45 + bodyOffset);
            param1.graphics.lineTo(-7.45,8.35 + bodyOffset);
            param1.graphics.lineTo(-8.55,7.4 + bodyOffset);
         }
         param1.graphics.endFill();
         if(food)
         {
            drawFoodSymbol(param1,symbolOffset,color);
         }
         else
         {
            drawDrinkSymbol(param1,symbolOffset,color);
         }
         if(positive && tier >= 2)
         {
            drawPositiveTierChevron(param1,false,color);
            if(tier >= 3)
            {
               drawPositiveTierChevron(param1,true,color);
            }
         }
         else if(!positive && tier >= 2)
         {
            drawNegativeTierChevron(param1,food ? 0 : -0.8,color);
         }
      }

      private static function drawFoodSymbol(param1:Shape, param2:Number, param3:uint) : void
      {
         param1.graphics.beginFill(CanvasChronomarkStyle.FACE_COLOR,1);
         param1.graphics.moveTo(-4.15,3.2 + param2);
         param1.graphics.lineTo(-3.1,3.1 + param2);
         param1.graphics.lineTo(-1.75,4.45 + param2);
         param1.graphics.lineTo(-6.85,9.6 + param2);
         param1.graphics.lineTo(-7.05,10 + param2);
         param1.graphics.lineTo(-6.85,10.45 + param2);
         param1.graphics.lineTo(-6.4,10.6 + param2);
         param1.graphics.lineTo(-6,10.45 + param2);
         param1.graphics.lineTo(-0.5,4.95 + param2);
         param1.graphics.lineTo(1.45,5.05 + param2);
         param1.graphics.lineTo(1.85,4.95 + param2);
         param1.graphics.lineTo(3,4.1 + param2);
         param1.graphics.lineTo(5,1 + param2);
         param1.graphics.lineTo(6.25,-1.65 + param2);
         param1.graphics.lineTo(6.2,-2.15 + param2);
         param1.graphics.lineTo(6.15,-2.3 + param2);
         param1.graphics.lineTo(6.05,-2.45 + param2);
         param1.graphics.lineTo(5.6,-2.65 + param2);
         param1.graphics.curveTo(5.35,-2.65 + param2,5.2,-2.45 + param2);
         param1.graphics.lineTo(-0.9,3.55 + param2);
         param1.graphics.lineTo(-2.25,2.2 + param2);
         param1.graphics.lineTo(-2.2,1.2 + param2);
         param1.graphics.lineTo(-2.2,0.85 + param2);
         param1.graphics.lineTo(-2.35,0.5 + param2);
         param1.graphics.lineTo(-5.95,-2.7 + param2);
         param1.graphics.lineTo(-6.1,-2.7 + param2);
         param1.graphics.lineTo(-6.15,-2.55 + param2);
         param1.graphics.lineTo(-3.5,0.6 + param2);
         param1.graphics.lineTo(-3.5,0.65 + param2);
         param1.graphics.lineTo(-3.65,0.8 + param2);
         param1.graphics.lineTo(-3.85,0.95 + param2);
         param1.graphics.lineTo(-6.7,-1.55 + param2);
         param1.graphics.lineTo(-6.75,-1.6 + param2);
         param1.graphics.lineTo(-6.9,-1.55 + param2);
         param1.graphics.lineTo(-6.9,-1.35 + param2);
         param1.graphics.lineTo(-4.4,1.45 + param2);
         param1.graphics.lineTo(-4.4,1.55 + param2);
         param1.graphics.lineTo(-4.55,1.75 + param2);
         param1.graphics.lineTo(-4.75,1.85 + param2);
         param1.graphics.lineTo(-7.85,-0.8 + param2);
         param1.graphics.lineTo(-7.95,-0.85 + param2);
         param1.graphics.lineTo(-8.05,-0.8 + param2);
         param1.graphics.lineTo(-8.1,-0.65 + param2);
         param1.graphics.lineTo(-4.8,2.95 + param2);
         param1.graphics.lineTo(-4.45,3.15 + param2);
         param1.graphics.lineTo(-4.15,3.2 + param2);
         param1.graphics.endFill();

         param1.graphics.beginFill(param3,1);
         param1.graphics.moveTo(5.15,9.6 + param2);
         param1.graphics.lineTo(1.15,5.65 + param2);
         param1.graphics.lineTo(-0.3,5.55 + param2);
         param1.graphics.lineTo(-0.5,5.7 + param2);
         param1.graphics.lineTo(4.25,10.45 + param2);
         param1.graphics.lineTo(4.7,10.6 + param2);
         param1.graphics.lineTo(5.15,10.45 + param2);
         param1.graphics.lineTo(5.3,10 + param2);
         param1.graphics.lineTo(5.15,9.6 + param2);
         param1.graphics.endFill();
      }

      private static function drawDrinkSymbol(param1:Shape, param2:Number, param3:uint) : void
      {
         param1.graphics.beginFill(CanvasChronomarkStyle.FACE_COLOR,1);
         param1.graphics.moveTo(-2.3,-0.45 + param2);
         param1.graphics.lineTo(-2.45,-1.2 + param2);
         param1.graphics.lineTo(-4,-3.75 + param2);
         param1.graphics.lineTo(-5.55,-1.2 + param2);
         param1.graphics.lineTo(-5.7,-0.45 + param2);
         param1.graphics.curveTo(-5.7,0.25 + param2,-5.25,0.75 + param2);
         param1.graphics.curveTo(-4.75,1.25 + param2,-4,1.25 + param2);
         param1.graphics.curveTo(-3.3,1.25 + param2,-2.75,0.75 + param2);
         param1.graphics.curveTo(-2.3,0.25 + param2,-2.3,-0.45 + param2);
         param1.graphics.endFill();

         param1.graphics.beginFill(CanvasChronomarkStyle.FACE_COLOR,1);
         param1.graphics.moveTo(4.6,6.5 + param2);
         param1.graphics.curveTo(4.6,5.5 + param2,4.1,4.7 + param2);
         param1.graphics.lineTo(0.7,-0.95 + param2);
         param1.graphics.lineTo(-2.7,4.7 + param2);
         param1.graphics.curveTo(-3.2,5.55 + param2,-3.2,6.5 + param2);
         param1.graphics.curveTo(-3.2,8.15 + param2,-2,9.25 + param2);
         param1.graphics.curveTo(-0.9,10.45 + param2,0.7,10.45 + param2);
         param1.graphics.curveTo(2.3,10.45 + param2,3.45,9.25 + param2);
         param1.graphics.curveTo(4.6,8.15 + param2,4.6,6.5 + param2);
         param1.graphics.endFill();

         param1.graphics.beginFill(param3,1);
         param1.graphics.moveTo(-4.85,0.4 + param2);
         param1.graphics.lineTo(-5.25,-0.4 + param2);
         param1.graphics.lineTo(-5.2,-0.6 + param2);
         param1.graphics.lineTo(-4.95,-0.75 + param2);
         param1.graphics.lineTo(-4.8,-0.6 + param2);
         param1.graphics.lineTo(-4.7,-0.45 + param2);
         param1.graphics.lineTo(-4.5,-0.05 + param2);
         param1.graphics.lineTo(-4,0.2 + param2);
         param1.graphics.lineTo(-3.8,0.3 + param2);
         param1.graphics.lineTo(-3.75,0.45 + param2);
         param1.graphics.lineTo(-3.85,0.65 + param2);
         param1.graphics.lineTo(-4.05,0.7 + param2);
         param1.graphics.curveTo(-4.6,0.65 + param2,-4.85,0.4 + param2);
         param1.graphics.endFill();

         param1.graphics.beginFill(param3,1);
         param1.graphics.moveTo(-1.45,8.7 + param2);
         param1.graphics.curveTo(-2.35,7.8 + param2,-2.45,6.7 + param2);
         param1.graphics.lineTo(-2.35,6.35 + param2);
         param1.graphics.lineTo(-2.05,6.2 + param2);
         param1.graphics.lineTo(-1.75,6.25 + param2);
         param1.graphics.lineTo(-1.6,6.55 + param2);
         param1.graphics.curveTo(-1.55,7.45 + param2,-0.9,8.1 + param2);
         param1.graphics.curveTo(-0.2,8.8 + param2,0.8,8.85 + param2);
         param1.graphics.lineTo(1.05,9 + param2);
         param1.graphics.lineTo(1.15,9.3 + param2);
         param1.graphics.lineTo(1,9.6 + param2);
         param1.graphics.lineTo(0.65,9.7 + param2);
         param1.graphics.curveTo(-0.55,9.6 + param2,-1.45,8.7 + param2);
         param1.graphics.endFill();
      }

      private static function drawPositiveTierChevron(param1:Shape, param2:Boolean, param3:uint) : void
      {
         var centerX:Number = -0.65;
         param1.graphics.beginFill(param3,1);
         if(param2)
         {
            param1.graphics.moveTo(centerX,-16.25);
            param1.graphics.lineTo(4.55,-12.3);
            param1.graphics.lineTo(4.7,-12.05);
            param1.graphics.lineTo(4.65,-11.75);
            param1.graphics.lineTo(4.4,-11.6);
            param1.graphics.lineTo(4.05,-11.7);
            param1.graphics.lineTo(centerX,-15.3);
            param1.graphics.lineTo(-5.45,-11.7);
            param1.graphics.curveTo(-5.55,-11.6,-5.7,-11.6);
            param1.graphics.lineTo(-6,-11.75);
            param1.graphics.lineTo(-6.1,-12);
            param1.graphics.lineTo(-5.9,-12.3);
            param1.graphics.lineTo(centerX,-16.25);
         }
         else
         {
            param1.graphics.moveTo(centerX,-13.9);
            param1.graphics.lineTo(4.75,-9.7);
            param1.graphics.lineTo(5.1,-9.15);
            param1.graphics.lineTo(4.95,-8.65);
            param1.graphics.lineTo(4.45,-8.3);
            param1.graphics.lineTo(3.85,-8.45);
            param1.graphics.lineTo(centerX,-11.9);
            param1.graphics.lineTo(-5.25,-8.45);
            param1.graphics.lineTo(-5.8,-8.3);
            param1.graphics.curveTo(-6.15,-8.35,-6.35,-8.65);
            param1.graphics.lineTo(-6.45,-9.15);
            param1.graphics.lineTo(-6.2,-9.7);
            param1.graphics.lineTo(centerX,-13.9);
         }
         param1.graphics.endFill();
      }

      private static function drawNegativeTierChevron(param1:Shape, param2:Number, param3:uint) : void
      {
         param1.graphics.beginFill(param3,1);
         param1.graphics.moveTo(-0.7,17.05 + param2);
         param1.graphics.lineTo(-6.15,12.9 + param2);
         param1.graphics.lineTo(-6.5,12.4 + param2);
         param1.graphics.lineTo(-6.35,11.8 + param2);
         param1.graphics.curveTo(-6.15,11.5 + param2,-5.8,11.45 + param2);
         param1.graphics.curveTo(-5.45,11.4 + param2,-5.25,11.6 + param2);
         param1.graphics.lineTo(-0.7,15.05 + param2);
         param1.graphics.lineTo(3.8,11.6 + param2);
         param1.graphics.curveTo(4.1,11.4 + param2,4.4,11.45 + param2);
         param1.graphics.curveTo(4.75,11.5 + param2,4.95,11.8 + param2);
         param1.graphics.lineTo(5.1,12.4 + param2);
         param1.graphics.lineTo(4.8,12.9 + param2);
         param1.graphics.lineTo(-0.7,17.05 + param2);
         param1.graphics.endFill();
      }

      private static function drawWave(param1:Shape, param2:Number) : void
      {
         param1.graphics.moveTo(-7,param2);
         param1.graphics.curveTo(-3,param2 - 3,0,param2);
         param1.graphics.curveTo(3,param2 + 3,7,param2);
      }

      private function createPool(param1:int, param2:Number, param3:Number, param4:Number = 18) : Array
      {
         var pool:Array = [];
         var index:int = 0;
         while(index < param1)
         {
            var display:Sprite = new Sprite();
            display.x = param3 + index * param4;
            display.y = param2;
            display.addChild(new Shape());
            display.visible = false;
            addChild(display);
            pool.push(display);
            index++;
         }
         return pool;
      }

      private function setEnvironmentAlpha(param1:Number) : void
      {
         var index:int = 0;
         while(index < this.environmentPool.length)
         {
            (this.environmentPool[index] as Sprite).alpha = CanvasChronomarkStyle.clamp(param1,0.15,1);
            index++;
         }
      }

   }
}
