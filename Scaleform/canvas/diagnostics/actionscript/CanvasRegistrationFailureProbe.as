package
{
   import flash.display.MovieClip;

   public final class CanvasRegistrationFailureProbe extends MovieClip
   {
      private var marker:CanvasDiagnosticMarker;

      private var registrationCount:int = 0;

      public function CanvasRegistrationFailureProbe()
      {
         this.marker = new CanvasDiagnosticMarker(this,"VWCANVAS REGISTRATION FAILURE PROBE",16744448);
         this.updateMarker();
      }

      public function getCanvasRegistration() : Object
      {
         this.registrationCount++;
         this.updateMarker();
         if(this.registrationCount == 1)
         {
            throw "REGISTRATION FAILURE PROBE STRING";
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
            "marker":"REGISTRATION-FAILURE-PROBE-TEST-ONLY"
         };
      }

      private function updateMarker() : void
      {
         if(this.marker != null)
         {
            this.marker.update([
               "REG " + this.registrationCount,
               "FIRST REGISTRATION THROWS NON-ERROR STRING"
            ]);
         }
      }
   }
}
