package
{
   import flash.display.Graphics;
   import flash.display.Shape;

   internal final class CanvasChronomarkIcons
   {
      public static function draw(param1:Shape, param2:Object, param3:String, param4:uint) : void
      {
         var iconType:int = param2 != null ? int(param2.iconType) : 0;
         var effectIcon:String = param2 != null && param2.icon != null ? String(param2.icon) : "";
         if(param2 != null && param2.isHazard === true)
         {
            iconType = CanvasChronomarkStyle.MARKER_HAZARD;
         }
         else if(iconType == 0 && param3 == "mission")
         {
            iconType = CanvasChronomarkStyle.MARKER_QUEST;
         }
         else if(iconType == 0 && param3 == "enemy")
         {
            iconType = CanvasChronomarkStyle.MARKER_ENEMY;
         }

         var graphics:Graphics = param1.graphics;
         graphics.clear();
         graphics.lineStyle(1.5,param4,1,true);
         switch(iconType)
         {
            case CanvasChronomarkStyle.MARKER_QUEST:
               drawQuest(graphics,false,false,param4);
               break;
            case CanvasChronomarkStyle.MARKER_QUEST_DOOR:
               drawQuest(graphics,true,false,param4);
               break;
            case CanvasChronomarkStyle.MARKER_QUEST_OFFPLANET:
               drawQuest(graphics,false,true,param4);
               break;
            case CanvasChronomarkStyle.MARKER_PLAYER_SET:
               drawPlayerSet(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_ENEMY:
               drawEnemy(graphics,false,param4);
               break;
            case CanvasChronomarkStyle.MARKER_ENEMY_TARGETED:
               drawEnemy(graphics,true,param4);
               break;
            case CanvasChronomarkStyle.MARKER_LOCATION:
               drawLocation(graphics,param2,param4);
               break;
            case CanvasChronomarkStyle.MARKER_COMPANION:
               drawCompanion(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_RECON:
               drawRecon(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_SHIP:
               drawShip(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_OUTPOST:
               drawOutpost(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_HAZARD:
               if(isKnownHazardEffect(effectIcon))
               {
                  CanvasChronomarkEffects.drawEffect(param1,param4,effectIcon);
               }
               else
               {
                  drawHazard(graphics,param4);
               }
               break;
            case CanvasChronomarkStyle.MARKER_VEHICLE:
               drawVehicle(graphics,param4);
               break;
            case CanvasChronomarkStyle.MARKER_POSITION:
            default:
               drawPosition(graphics,param4);
         }
         drawSubCategory(graphics,param2 != null ? int(param2.mapMarkerSubCategoryType) : 0,param4);
      }

      private static function drawQuest(param1:Graphics, param2:Boolean, param3:Boolean, param4:uint) : void
      {
         param1.beginFill(param4,0.82);
         param1.moveTo(0,-7);
         param1.lineTo(7,0);
         param1.lineTo(0,7);
         param1.lineTo(-7,0);
         param1.lineTo(0,-7);
         param1.endFill();
         if(param2)
         {
            param1.lineStyle(1,0,0.9,true);
            param1.drawRect(-2.5,-3,5,7);
            param1.drawCircle(1,0.5,0.5);
         }
         else if(param3)
         {
            param1.lineStyle(1,0,0.9,true);
            param1.drawCircle(0,0,3);
            param1.moveTo(-5,0);
            param1.curveTo(0,-3,5,0);
            param1.curveTo(0,3,-5,0);
         }
      }

      private static function drawPlayerSet(param1:Graphics, param2:uint) : void
      {
         param1.beginFill(param2,0.75);
         param1.drawCircle(0,-2,4.5);
         param1.moveTo(-3,1);
         param1.lineTo(0,8);
         param1.lineTo(3,1);
         param1.lineTo(-3,1);
         param1.endFill();
         param1.lineStyle(1,0,0.8,true);
         param1.drawCircle(0,-2,1.5);
      }

      private static function drawEnemy(param1:Graphics, param2:Boolean, param3:uint) : void
      {
         param1.beginFill(param3,0.38);
         param1.moveTo(-7,5);
         param1.lineTo(0,-7);
         param1.lineTo(7,5);
         param1.lineTo(3,3);
         param1.lineTo(0,-2);
         param1.lineTo(-3,3);
         param1.lineTo(-7,5);
         param1.endFill();
         if(param2)
         {
            drawTargetBrackets(param1,param3);
         }
      }

      private static function drawLocation(param1:Graphics, param2:Object, param3:uint) : void
      {
         var category:int = param2 != null ? int(param2.mapMarkerCategory) : 0;
         var state:int = param2 != null ? int(param2.locationMarkerState) : 0;
         param1.beginFill(param3,state >= 2 ? 0.28 : 0.08);
         param1.drawCircle(0,0,7);
         param1.endFill();
         if(category == 2 || category == 7)
         {
            param1.drawRect(-3.5,-3.5,7,7);
         }
         else if(category == 3)
         {
            param1.moveTo(0,5);
            param1.curveTo(-7,0,0,-6);
            param1.curveTo(7,0,0,5);
         }
         else if(category == 4)
         {
            param1.moveTo(0,-5);
            param1.lineTo(5,4);
            param1.lineTo(-5,4);
            param1.lineTo(0,-5);
         }
         else if(category == 6)
         {
            param1.moveTo(0,-5);
            param1.lineTo(4,4);
            param1.lineTo(0,2);
            param1.lineTo(-4,4);
            param1.lineTo(0,-5);
         }
         else
         {
            param1.drawCircle(0,0,2.5);
         }
         if(state == 1)
         {
            param1.moveTo(-2,6);
            param1.lineTo(2,6);
         }
         else if(state >= 2)
         {
            param1.beginFill(param3,0.9);
            param1.drawCircle(0,0,1.25);
            param1.endFill();
         }
      }

      private static function drawCompanion(param1:Graphics, param2:uint) : void
      {
         param1.drawCircle(0,-3,2.5);
         param1.moveTo(-5,6);
         param1.curveTo(-4,0,0,0);
         param1.curveTo(4,0,5,6);
         param1.drawCircle(0,0,7);
      }

      private static function drawRecon(param1:Graphics, param2:uint) : void
      {
         param1.drawCircle(0,0,6);
         param1.drawCircle(0,0,2);
         param1.moveTo(-9,0);
         param1.lineTo(-4,0);
         param1.moveTo(4,0);
         param1.lineTo(9,0);
         param1.moveTo(0,-9);
         param1.lineTo(0,-4);
         param1.moveTo(0,4);
         param1.lineTo(0,9);
      }

      private static function drawShip(param1:Graphics, param2:uint) : void
      {
         param1.beginFill(param2,0.45);
         param1.moveTo(0,-8);
         param1.lineTo(6,6);
         param1.lineTo(0,3);
         param1.lineTo(-6,6);
         param1.lineTo(0,-8);
         param1.endFill();
         param1.moveTo(0,3);
         param1.lineTo(0,8);
      }

      private static function drawOutpost(param1:Graphics, param2:uint) : void
      {
         param1.moveTo(-7,-1);
         param1.lineTo(0,-7);
         param1.lineTo(7,-1);
         param1.lineTo(5,-1);
         param1.lineTo(5,6);
         param1.lineTo(-5,6);
         param1.lineTo(-5,-1);
         param1.lineTo(-7,-1);
         param1.moveTo(-1,6);
         param1.lineTo(-1,1);
         param1.lineTo(2,1);
         param1.lineTo(2,6);
      }

      private static function drawHazard(param1:Graphics, param2:uint) : void
      {
         param1.beginFill(param2,0.28);
         param1.moveTo(0,-8);
         param1.lineTo(8,6);
         param1.lineTo(-8,6);
         param1.lineTo(0,-8);
         param1.endFill();
         param1.moveTo(0,-3.5);
         param1.lineTo(0,2);
         param1.drawCircle(0,4,0.75);
      }

      private static function isKnownHazardEffect(param1:String) : Boolean
      {
         switch(param1)
         {
            case "HazardEffect_Radiation":
            case "HazardEffect_Thermal":
            case "HazardEffect_Airborne":
            case "HazardEffect_Corrosive":
            case "HazardEffect_RestoreSoak":
               return true;
         }
         return false;
      }

      private static function drawPosition(param1:Graphics, param2:uint) : void
      {
         param1.drawCircle(0,0,4);
         param1.beginFill(param2,0.9);
         param1.drawCircle(0,0,1.5);
         param1.endFill();
         param1.moveTo(0,-8);
         param1.lineTo(0,-4);
      }

      private static function drawVehicle(param1:Graphics, param2:uint) : void
      {
         param1.drawRoundRect(-7,-4,14,8,2,2);
         param1.moveTo(-4,-4);
         param1.lineTo(-2,-7);
         param1.lineTo(3,-7);
         param1.lineTo(5,-4);
         param1.drawCircle(-4,5,2);
         param1.drawCircle(4,5,2);
      }

      private static function drawSubCategory(param1:Graphics, param2:int, param3:uint) : void
      {
         if(param2 == 1)
         {
            param1.lineStyle(1,param3,0.55,true);
            param1.drawCircle(0,0,9);
         }
         else if(param2 == 2)
         {
            param1.lineStyle(1,param3,0.9,true);
            param1.drawCircle(0,0,9);
         }
         else if(param2 == 3)
         {
            drawTargetBrackets(param1,param3);
         }
      }

      private static function drawTargetBrackets(param1:Graphics, param2:uint) : void
      {
         param1.lineStyle(1,param2,1,true);
         param1.moveTo(-9,-5);
         param1.lineTo(-9,-9);
         param1.lineTo(-5,-9);
         param1.moveTo(5,-9);
         param1.lineTo(9,-9);
         param1.lineTo(9,-5);
         param1.moveTo(9,5);
         param1.lineTo(9,9);
         param1.lineTo(5,9);
         param1.moveTo(-5,9);
         param1.lineTo(-9,9);
         param1.lineTo(-9,5);
      }
   }
}
