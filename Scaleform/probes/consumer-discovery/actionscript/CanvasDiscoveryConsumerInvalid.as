package
{
   import flash.display.MovieClip;

   public final class CanvasDiscoveryConsumerInvalid extends MovieClip
   {
      public function getCanvasDiscoveryRecord() : Object
      {
         return {
            "protocol":"VWCANVAS_DISCOVERY_PROBE/0-INVALID",
            "slot":"slot-00",
            "consumerId":"",
            "version":"0.0.0",
            "marker":"INVALID"
         };
      }

      public function dispose() : void
      {
      }
   }
}
