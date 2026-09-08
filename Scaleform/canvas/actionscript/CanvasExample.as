package
{
   import flash.display.MovieClip;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasExample extends MovieClip
   {
      private var marker:TextField;
      private var pingReceived:Boolean;

      public function CanvasExample()
      {
         this.marker = this.createMarker("VWCANVAS EXAMPLE",16776960);
      }

      public function getCanvasRegistration() : Object
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
            "marker":"EXAMPLE"
         };
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
         if(this.marker != null && !this.pingReceived && param1 == "PlayerData")
         {
            this.marker.text = "VWCANVAS EXAMPLE | DATA " + param1;
         }
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         if(this.marker != null && param1 == "venworks.canvas.example.ping")
         {
            this.pingReceived = true;
            this.marker.text = "pong";
         }
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(this.marker != null && !this.pingReceived && param1 == "ready")
         {
            this.marker.text = "VWCANVAS EXAMPLE | READY V" + param2.contractVersion;
         }
      }

      public function dispose() : void
      {
         if(this.marker != null && this.marker.parent === this)
         {
            removeChild(this.marker);
         }
         this.marker = null;
      }

      private function createMarker(param1:String, param2:uint) : TextField
      {
         var format:TextFormat = new TextFormat("$MAIN_Font_Bold",18,param2,true);
         var field:TextField = new TextField();
         field.x = 500;
         field.y = 720;
         field.width = 620;
         field.height = 36;
         field.background = true;
         field.backgroundColor = 2097152;
         field.border = true;
         field.borderColor = param2;
         field.embedFonts = true;
         field.defaultTextFormat = format;
         field.text = param1 + " | " + this.resolveUrl();
         field.setTextFormat(format);
         field.selectable = false;
         field.mouseEnabled = false;
         addChild(field);
         return field;
      }

      private function resolveUrl() : String
      {
         var movieUrl:String = "url-unavailable";
         try
         {
            movieUrl = loaderInfo.url;
         }
         catch(urlError:Error)
         {
         }
         return movieUrl;
      }
   }
}
