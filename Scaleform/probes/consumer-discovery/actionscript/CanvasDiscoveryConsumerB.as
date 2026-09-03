package
{
   import flash.display.MovieClip;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasDiscoveryConsumerB extends MovieClip
   {
      private var marker:TextField;

      public function CanvasDiscoveryConsumerB()
      {
         this.marker = this.createMarker("VWCANVAS-9 CONSUMER B",65535);
      }

      public function getCanvasDiscoveryRecord() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/1",
            "consumerId":"beef70b2-024e-4e9b-a8d5-70a0c882c431",
            "assetNamespace":"venworks.canvas.probe.consumer-b",
            "version":1,
            "marker":"B"
         };
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
