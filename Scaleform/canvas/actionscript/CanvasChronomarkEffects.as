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
         this.sustenancePool = this.createPool(CanvasChronomarkStyle.SUSTENANCE_EFFECT_CAPACITY,91,101.5);
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
         else if(style == "food-positive" || style == "food-negative")
         {
            shape.graphics.drawCircle(1,1,5);
            shape.graphics.drawCircle(1,1,2);
            shape.graphics.moveTo(-7,-6);
            shape.graphics.lineTo(-7,7);
            shape.graphics.moveTo(-9,-2);
            shape.graphics.lineTo(-5,-2);
            if(style == "food-positive")
            {
               shape.graphics.moveTo(4,-7);
               shape.graphics.lineTo(4,-3);
               shape.graphics.moveTo(2,-5);
               shape.graphics.lineTo(6,-5);
            }
            else
            {
               shape.graphics.moveTo(-5,-6);
               shape.graphics.lineTo(7,6);
            }
         }
         else if(style == "drink-positive" || style == "drink-negative")
         {
            shape.graphics.moveTo(-5,-6);
            shape.graphics.lineTo(-3,7);
            shape.graphics.lineTo(4,7);
            shape.graphics.lineTo(6,-6);
            shape.graphics.lineTo(-5,-6);
            shape.graphics.moveTo(-4,1);
            shape.graphics.lineTo(5,1);
            if(style == "drink-positive")
            {
               shape.graphics.moveTo(0,-5);
               shape.graphics.lineTo(0,-1);
               shape.graphics.moveTo(-2,-3);
               shape.graphics.lineTo(2,-3);
            }
            else
            {
               shape.graphics.moveTo(-6,-7);
               shape.graphics.lineTo(7,7);
            }
         }
         else
         {
            shape.graphics.drawCircle(0,0,5);
            shape.graphics.drawCircle(0,0,1);
         }
      }

      private static function drawWave(param1:Shape, param2:Number) : void
      {
         param1.graphics.moveTo(-7,param2);
         param1.graphics.curveTo(-3,param2 - 3,0,param2);
         param1.graphics.curveTo(3,param2 + 3,7,param2);
      }

      private function createPool(param1:int, param2:Number, param3:Number) : Array
      {
         var pool:Array = [];
         var index:int = 0;
         while(index < param1)
         {
            var display:Sprite = new Sprite();
            display.x = param3 + index * 18;
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
