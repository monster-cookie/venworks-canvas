package
{
   import flash.display.MovieClip;

   public final class CanvasReadyFailureProbe extends MovieClip
   {
      private var marker:CanvasDiagnosticMarker;

      private var registrationCount:int = 0;

      private var readyCount:int = 0;

      private var unloadCount:int = 0;

      public function CanvasReadyFailureProbe()
      {
         this.marker = new CanvasDiagnosticMarker(this,"VWCANVAS READY FAILURE PROBE",16776960);
         this.updateMarker();
      }

      public function getCanvasRegistration() : Object
      {
         this.registrationCount++;
         this.updateMarker();
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
            throw "READY FAILURE PROBE STRING";
         }
         if(param1 == "unload")
         {
            this.unloadCount++;
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
            "marker":"READY-FAILURE-PROBE-TEST-ONLY"
         };
      }

      private function updateMarker() : void
      {
         if(this.marker != null)
         {
            this.marker.update([
               "REG " + this.registrationCount + " | READY " + this.readyCount + " | UNLOAD " + this.unloadCount,
               "READY THROWS NON-ERROR STRING"
            ]);
         }
      }
   }
}
