package
{
   import flash.display.MovieClip;
   import flash.text.TextField;
   import flash.text.TextFormat;

   public final class CanvasDiscoveryConsumerA extends MovieClip
   {
      private var marker:TextField;

      public function CanvasDiscoveryConsumerA()
      {
         this.marker = this.createMarker("VWCANVAS-9 CONSUMER A",16776960);
      }

      public function getCanvasDiscoveryRecord() : Object
      {
         return {
            "protocol":"VWCANVAS_CONSUMER/1",
            "consumerId":"venworks.canvas.probe.consumer-a",
            "version":1,
            "marker":"A"
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
