package
{
   import flash.display.MovieClip;
   import flash.events.Event;

   public final class CanvasCallbackProbe extends MovieClip
   {
      private var marker:CanvasDiagnosticMarker;

      private var registrationCount:int = 0;

      private var readyCount:int = 0;

      private var dataCount:int = 0;

      private var eventCount:int = 0;

      private var unloadCount:int = 0;

      private var disposeCount:int = 0;

      private var initInjectionCount:int = 0;

      private var completeInjectionCount:int = 0;

      private var initInjected:Boolean = false;

      private var completeInjected:Boolean = false;

      public function CanvasCallbackProbe()
      {
         this.marker = new CanvasDiagnosticMarker(this,"VWCANVAS CALLBACK PROBE",16711935);
         this.updateMarker();
      }

      public function getCanvasRegistration() : Object
      {
         this.registrationCount++;
         if(!this.initInjected)
         {
            this.initInjected = true;
            this.initInjectionCount++;
            this.updateMarker();
            loaderInfo.dispatchEvent(new Event(Event.INIT));
         }
         return this.createRegistration();
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
         this.dataCount++;
         this.updateMarker();
         if(this.dataCount % 2 == 1)
         {
            throw new Error("CALLBACK PROBE DATA ERROR");
         }
         throw "CALLBACK PROBE DATA STRING";
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         this.eventCount++;
         this.updateMarker();
         if(this.eventCount % 2 == 1)
         {
            throw new Error("CALLBACK PROBE EVENT ERROR");
         }
         throw "CALLBACK PROBE EVENT STRING";
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(param1 == "ready")
         {
            this.readyCount++;
            if(!this.completeInjected)
            {
               this.completeInjected = true;
               this.completeInjectionCount++;
               this.updateMarker();
               loaderInfo.dispatchEvent(new Event(Event.COMPLETE));
            }
            this.updateMarker();
         }
         else if(param1 == "unload")
         {
            this.unloadCount++;
            this.updateMarker();
            throw new Error("CALLBACK PROBE UNLOAD ERROR");
         }
      }

      public function dispose() : void
      {
         this.disposeCount++;
         this.updateMarker();
         if(this.marker != null)
         {
            this.marker.dispose();
            this.marker = null;
         }
         throw "CALLBACK PROBE DISPOSE STRING";
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
            "marker":"CALLBACK-PROBE-TEST-ONLY"
         };
      }

      private function updateMarker() : void
      {
         if(this.marker == null)
         {
            return;
         }
         this.marker.update([
            "REG " + this.registrationCount + " | READY " + this.readyCount + " | DATA " + this.dataCount + " | EVENT " + this.eventCount,
            "DUP INIT " + this.initInjectionCount + " | DUP COMPLETE " + this.completeInjectionCount,
            "UNLOAD " + this.unloadCount + " | DISPOSE " + this.disposeCount,
            "DATA/EVENT ALTERNATE ERROR THEN STRING"
         ]);
      }
   }
}
