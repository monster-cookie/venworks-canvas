package
{
   import flash.display.MovieClip;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasComponentGallery extends MovieClip
   {
      private var marker:TextField;

      public function CanvasComponentGallery()
      {
         this.marker = this.createMarker("VWCANVAS COMPONENT GALLERY",65535);
      }

      public function getCanvasRegistration() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/2",
            "consumerId":"beef70b2-024e-4e9b-a8d5-70a0c882c431",
            "assetNamespace":"venworks.canvas.component-gallery",
            "version":1,
            "minimumContractVersion":2,
            "maximumContractVersion":2,
            "uiChannels":["PlayerData"],
            "eventTopics":["venworks.canvas.example.ping"],
            "marker":"COMPONENT-GALLERY"
         };
      }

      public function handleUIData(param1:String, param2:Object) : void
      {
         if(this.marker != null && param1 == "PlayerData")
         {
            this.marker.text = "VWCANVAS COMPONENT GALLERY | DATA " + param1;
         }
      }

      public function handleCanvasEvent(param1:String, param2:String) : void
      {
         if(this.marker != null && param1 == "venworks.canvas.example.ping")
         {
            this.marker.text = "VWCANVAS COMPONENT GALLERY | EVENT " + param2.substr(0,32);
         }
      }

      public function handleLifecycle(param1:String, param2:Object) : void
      {
         if(this.marker != null && param1 == "ready")
         {
            this.marker.text = "VWCANVAS COMPONENT GALLERY | READY V" + param2.contractVersion;
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
         field.x = 1140;
         field.y = 720;
         field.width = 500;
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
