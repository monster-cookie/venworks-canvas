package
{
   import flash.display.Shape;
   import flash.display.Sprite;

   internal final class CanvasChronomarkMarkers extends Sprite
   {
      private static const NEAR_RADIUS:Number = 126;

      private static const FAR_RADIUS:Number = 118.5;

      private static const OUTLINE_RADIUS:Number = 111;

      private var generalPool:Array;

      private var missionPool:Array;

      private var enemyPool:Array;

      private var compassMarkers:Array;

      private var hazardMarkers:Array;

      private var missionMarkers:Array;

      private var enemyMarkers:Array;

      private var direction:Number = 0;

      public function CanvasChronomarkMarkers()
      {
         super();
         mouseEnabled = false;
         mouseChildren = false;
         this.generalPool = this.createPool(CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY,CanvasChronomarkStyle.TEXT_COLOR,"general");
         this.missionPool = this.createPool(CanvasChronomarkStyle.MISSION_MARKER_CAPACITY,16771919,"mission");
         this.enemyPool = this.createPool(CanvasChronomarkStyle.ENEMY_MARKER_CAPACITY,CanvasChronomarkStyle.ALERT_COLOR,"enemy");
         this.compassMarkers = [];
         this.hazardMarkers = [];
         this.missionMarkers = [];
         this.enemyMarkers = [];
      }

      public function setCompass(param1:Object) : void
      {
         this.direction = param1 != null ? Number(param1.direction) : 0;
         this.compassMarkers = param1 != null && param1.markers is Array ? (param1.markers as Array).concat() : [];
         this.missionMarkers = param1 != null && param1.missionMarkers is Array ? (param1.missionMarkers as Array).concat() : [];
         this.enemyMarkers = param1 != null && param1.enemyMarkers is Array ? (param1.enemyMarkers as Array).concat() : [];
         this.render();
      }

      public function setHazards(param1:Array) : void
      {
         this.hazardMarkers = param1 == null ? [] : param1.concat();
         this.render();
      }

      public function dispose() : void
      {
         this.compassMarkers = [];
         this.hazardMarkers = [];
         this.missionMarkers = [];
         this.enemyMarkers = [];
         this.generalPool = [];
         this.missionPool = [];
         this.enemyPool = [];
         while(numChildren > 0)
         {
            removeChildAt(numChildren - 1);
         }
      }

      private function render() : void
      {
         var combined:Array = [];
         var handles:Object = {};
         var index:int = 0;
         var marker:Object = null;
         while(index < this.hazardMarkers.length && combined.length < CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY)
         {
            marker = this.hazardMarkers[index];
            if(marker != null && uint(marker.handle) > 0 && !handles.hasOwnProperty("$" + marker.handle))
            {
               marker.isHazard = true;
               handles["$" + marker.handle] = true;
               combined.push(marker);
            }
            index++;
         }
         index = 0;
         while(index < this.compassMarkers.length && combined.length < CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY)
         {
            marker = this.compassMarkers[index];
            if(marker != null && uint(marker.handle) > 0 && !handles.hasOwnProperty("$" + marker.handle))
            {
               handles["$" + marker.handle] = true;
               combined.push(marker);
            }
            index++;
         }
         this.renderPool(this.generalPool,combined,"general");
         this.renderPool(this.missionPool,this.missionMarkers,"mission");
         this.renderPool(this.enemyPool,this.enemyMarkers,"enemy");
      }

      private function renderPool(param1:Array, param2:Array, param3:String) : void
      {
         var index:int = 0;
         while(index < param1.length)
         {
            var display:Sprite = param1[index] as Sprite;
            if(index < param2.length && param2[index] != null)
            {
               this.positionMarker(display,param2[index],param3);
               display.visible = true;
            }
            else
            {
               display.visible = false;
            }
            index++;
         }
      }

      private function positionMarker(param1:Sprite, param2:Object, param3:String) : void
      {
         var heading:Number = Number(param2.heading);
         if(!isFinite(heading))
         {
            heading = 0;
         }
         var relative:Number = Math.PI - this.direction + heading;
         var outline:Boolean = param3 == "mission" || param3 == "enemy";
         var radius:Number = outline ? OUTLINE_RADIUS : param2.isNear === true ? NEAR_RADIUS : FAR_RADIUS;
         param1.x = CanvasChronomarkStyle.FACE_CENTER_X - Math.sin(relative) * radius;
         param1.y = CanvasChronomarkStyle.FACE_CENTER_Y + Math.cos(relative) * radius + (param3 == "general" && int(param2.iconType) != CanvasChronomarkStyle.LOCATION_MARKER_TYPE ? 15 : 0);
         param1.scaleX = param1.scaleY = CanvasChronomarkStyle.clamp(Number(param2.scale),0.4,1.6);
         param1.alpha = CanvasChronomarkStyle.clamp(Number(param2.alpha),0.15,1);
         if(outline)
         {
            param1.rotation = (heading - this.direction) * 180 / Math.PI;
         }
         else if(param2.isHazard === true)
         {
            param1.rotation = -(this.direction - heading) * 180 / Math.PI;
         }
         else
         {
            param1.rotation = 0;
         }
      }

      private function createPool(param1:int, param2:uint, param3:String) : Array
      {
         var pool:Array = [];
         var index:int = 0;
         while(index < param1)
         {
            var marker:Sprite = new Sprite();
            var shape:Shape = new Shape();
            shape.graphics.lineStyle(1,param2,1,true);
            if(param3 == "mission")
            {
               shape.graphics.beginFill(param2,0.85);
               shape.graphics.moveTo(0,-5);
               shape.graphics.lineTo(5,0);
               shape.graphics.lineTo(0,5);
               shape.graphics.lineTo(-5,0);
               shape.graphics.lineTo(0,-5);
               shape.graphics.endFill();
            }
            else if(param3 == "enemy")
            {
               shape.graphics.moveTo(-5,4);
               shape.graphics.lineTo(0,-5);
               shape.graphics.lineTo(5,4);
               shape.graphics.lineTo(-5,4);
            }
            else
            {
               shape.graphics.drawCircle(0,0,3.5);
               shape.graphics.moveTo(0,-7);
               shape.graphics.lineTo(0,-3.5);
            }
            marker.addChild(shape);
            marker.visible = false;
            addChild(marker);
            pool.push(marker);
            index++;
         }
         return pool;
      }
   }
}
