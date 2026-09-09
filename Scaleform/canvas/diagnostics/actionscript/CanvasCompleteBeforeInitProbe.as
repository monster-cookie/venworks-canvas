package
{
   import flash.display.MovieClip;
   import flash.events.Event;

   public final class CanvasCompleteBeforeInitProbe extends MovieClip
   {
      private var marker:CanvasDiagnosticMarker;

      private var registrationCount:int = 0;

      private var readyCount:int = 0;

      private var completeInjectionCount:int = 0;

      private var completeInjected:Boolean = false;

      public function CanvasCompleteBeforeInitProbe()
      {
         this.marker = new CanvasDiagnosticMarker(this,"VWCANVAS COMPLETE BEFORE INIT PROBE",65535);
         this.updateMarker();
      }

      public function getCanvasRegistration() : Object
      {
         this.registrationCount++;
         if(!this.completeInjected)
         {
            this.completeInjected = true;
            this.completeInjectionCount++;
            this.updateMarker();
            loaderInfo.dispatchEvent(new Event(Event.COMPLETE));
         }
         return this.createRegistration();
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(param1 == "ready")
         {
            this.readyCount++;
            this.updateMarker();
         }
      }

      public function dispose() : void
      {
         if(this.marker != null)
         {
            this.marker.dispose();
            this.marker = null;
         }
      }

      private function createRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/2",
            "consumerId":"a8098c1a-f86e-4b1e-9d7c-5a102bf38460",
            "assetNamespace":"venworks.canvas.example",
            "version":1,
            "minimumContractVersion":2,
            "maximumContractVersion":2,
            "uiChannels":["PlayerData"],
            "eventTopics":["venworks.canvas.example.ping"],
            "marker":"COMPLETE-BEFORE-INIT-PROBE-TEST-ONLY"
         };
      }

      private function updateMarker() : void
      {
         if(this.marker != null)
         {
            this.marker.update([
               "REG " + this.registrationCount + " | READY " + this.readyCount,
               "EARLY COMPLETE " + this.completeInjectionCount
            ]);
         }
      }
   }
}
