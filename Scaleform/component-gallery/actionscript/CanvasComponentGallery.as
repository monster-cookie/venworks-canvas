package
{
   import flash.display.MovieClip;

   public final class CanvasComponentGallery extends MovieClip
   {
      public function CanvasComponentGallery()
      {
         super();
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

      public function getCanvasHtmlRegistration() : Object
      {
         return {
            "contract":"VWCANVAS_HTML/2",
            "entryDocument":"index.html"
         };
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
      }
   }
}
