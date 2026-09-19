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

      private var generalAppearance:Array;

      private var missionAppearance:Array;

      private var enemyAppearance:Array;

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
         this.generalPool = this.createPool(CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY);
         this.missionPool = this.createPool(CanvasChronomarkStyle.MISSION_MARKER_CAPACITY);
         this.enemyPool = this.createPool(CanvasChronomarkStyle.ENEMY_MARKER_CAPACITY);
         this.generalAppearance = this.createAppearanceCache(CanvasChronomarkStyle.GENERAL_MARKER_CAPACITY);
         this.missionAppearance = this.createAppearanceCache(CanvasChronomarkStyle.MISSION_MARKER_CAPACITY);
         this.enemyAppearance = this.createAppearanceCache(CanvasChronomarkStyle.ENEMY_MARKER_CAPACITY);
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
         this.generalAppearance = [];
         this.missionAppearance = [];
         this.enemyAppearance = [];
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
         this.renderPool(this.generalPool,combined,"general",this.generalAppearance);
         this.renderPool(this.missionPool,this.missionMarkers,"mission",this.missionAppearance);
         this.renderPool(this.enemyPool,this.enemyMarkers,"enemy",this.enemyAppearance);
      }

      private function renderPool(param1:Array, param2:Array, param3:String, param4:Array) : void
      {
         var index:int = 0;
         while(index < param1.length)
         {
            var display:Sprite = param1[index] as Sprite;
            if(index < param2.length && param2[index] != null)
            {
               this.positionMarker(display,param2[index],param3,param4[index]);
               display.visible = true;
            }
            else
            {
               display.visible = false;
            }
            index++;
         }
      }

      private function positionMarker(param1:Sprite, param2:Object, param3:String, param4:Object) : void
      {
         var color:uint = param3 == "mission" ? 16771919 : (param3 == "enemy" || param2.isHazard === true ? CanvasChronomarkStyle.ALERT_COLOR : CanvasChronomarkStyle.TEXT_COLOR);
         var effectIcon:String = param2.icon != null ? String(param2.icon) : "";
         var iconKey:String = param3 + "|" + color + "|" + int(param2.iconType) + "|" + int(param2.mapMarkerType) + "|" + int(param2.mapMarkerCategory) + "|" + int(param2.locationMarkerState) + "|" + int(param2.mapMarkerSubCategoryType) + "|" + (param2.isHazard === true ? 1 : 0) + "|" + effectIcon;
         if(param4.iconKey !== iconKey)
         {
            CanvasChronomarkIcons.draw(param1.getChildAt(0) as Shape,param2,param3,color);
            param4.iconKey = iconKey;
         }
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
         param1.scaleX = param1.scaleY = CanvasChronomarkStyle.clamp(Number(param2.scale),0.4,1.6) * CanvasChronomarkStyle.MARKER_DISPLAY_SCALE;
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
         var relativeHeight:int = int(param2.relativeHeight);
         if(param4.relativeHeight !== relativeHeight)
         {
            this.renderRelativeHeight(param1,relativeHeight,param3);
            param4.relativeHeight = relativeHeight;
         }
         else
         {
            (param1.getChildAt(1) as Shape).rotation = -param1.rotation;
         }
      }

      private function renderRelativeHeight(param1:Sprite, param2:int, param3:String) : void
      {
         var cue:Shape = param1.getChildAt(1) as Shape;
         cue.graphics.clear();
         cue.rotation = -param1.rotation;
         if(param2 < 1 || param2 > 3)
         {
            return;
         }
         var color:uint = param3 == "mission" ? 16771919 : param3 == "enemy" ? CanvasChronomarkStyle.ALERT_COLOR : CanvasChronomarkStyle.TEXT_COLOR;
         cue.graphics.lineStyle(1,color,1,true);
         if(param2 == 1)
         {
            cue.graphics.moveTo(-3,-2);
            cue.graphics.lineTo(0,1);
            cue.graphics.lineTo(3,-2);
         }
         else if(param2 == 2)
         {
            cue.graphics.moveTo(-3,0);
            cue.graphics.lineTo(3,0);
         }
         else
         {
            cue.graphics.moveTo(-3,2);
            cue.graphics.lineTo(0,-1);
            cue.graphics.lineTo(3,2);
         }
      }

      private function createPool(param1:int) : Array
      {
         var pool:Array = [];
         var index:int = 0;
         while(index < param1)
         {
            var marker:Sprite = new Sprite();
            var shape:Shape = new Shape();
            marker.addChild(shape);
            var relativeHeightCue:Shape = new Shape();
            relativeHeightCue.y = 9;
            marker.addChild(relativeHeightCue);
            marker.visible = false;
            addChild(marker);
            pool.push(marker);
            index++;
         }
         return pool;
      }

      private function createAppearanceCache(param1:int) : Array
      {
         var result:Array = [];
         var index:int = 0;
         while(index < param1)
         {
            result.push({"iconKey":"","relativeHeight":-1});
            index++;
         }
         return result;
      }
   }
}
