package
{
   // Consoles crash if a graphics command uses a coordinate outside the stage. PC does not.
   public final class CanvasStageGuard
   {
      public static var screenWidth:Number = 1920;

      public static var screenHeight:Number = 1080;

      public static var reporter:Function;

      private static var reported:Boolean = false;

      public static function setScreen(width:Number, height:Number) : void
      {
         if(isFinite(width) && width > 0) screenWidth = width;
         if(isFinite(height) && height > 0) screenHeight = height;
         reported = false;
      }

      public static function place(x:Number, y:Number) : Array
      {
         var nextX:Number = x;
         var nextY:Number = y;
         // A fraction of a pixel past the edge is the icon viewBox, not a draw off the screen.
         var outside:Boolean = !isFinite(nextX) || !isFinite(nextY) || nextX < -1 || nextY < -1 || nextX > screenWidth + 1 || nextY > screenHeight + 1;
         if(!isFinite(nextX) || nextX < 0) nextX = 0;
         else if(nextX > screenWidth) nextX = screenWidth;
         if(!isFinite(nextY) || nextY < 0) nextY = 0;
         else if(nextY > screenHeight) nextY = screenHeight;
         if(outside) note(x,y);
         return [nextX,nextY];
      }

      public static function rectangle(x:Number, y:Number, width:Number, height:Number) : Array
      {
         var right:Number = x + width;
         var bottom:Number = y + height;
         if(!isFinite(x) || !isFinite(y) || !isFinite(right) || !isFinite(bottom) || x < -1 || y < -1 || right > screenWidth + 1 || bottom > screenHeight + 1) note(x,y);
         var left:Number = !isFinite(x) || x < 0 ? 0 : (x > screenWidth ? screenWidth : x);
         var top:Number = !isFinite(y) || y < 0 ? 0 : (y > screenHeight ? screenHeight : y);
         var far:Number = !isFinite(right) || right < 0 ? 0 : (right > screenWidth ? screenWidth : right);
         var low:Number = !isFinite(bottom) || bottom < 0 ? 0 : (bottom > screenHeight ? screenHeight : bottom);
         return [left,top,Math.max(0,far - left),Math.max(0,low - top)];
      }

      private static function note(x:Number, y:Number) : void
      {
         if(reported) return;
         reported = true;
         var message:String = "ERROR: DRAW OUTSIDE STAGE | something tried to draw outside the stage/screen bounds at " + x + "," + y + " (screen " + screenWidth + "x" + screenHeight + ")";
         if(reporter != null) reporter(message);
         else trace(message);
      }
   }
}
