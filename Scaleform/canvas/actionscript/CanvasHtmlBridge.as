package
{
   public final class CanvasHtmlBridge
   {
      private var session:CanvasHtmlSession;

      public function CanvasHtmlBridge(param1:CanvasHtmlSession)
      {
         this.session = param1;
      }

      public function setData(param1:Object) : void
      {
         if(this.session != null)
         {
            this.session.setData(param1);
         }
      }

      public function setViewport(param1:Number, param2:Number) : void
      {
         if(this.session != null)
         {
            this.session.setViewport(param1,param2);
         }
      }

      public function scrollBy(param1:Number) : void
      {
         if(this.session != null)
         {
            this.session.scrollBy(param1);
         }
      }

      public function dispatch(param1:String) : void
      {
         if(this.session != null)
         {
            this.session.dispatch(param1);
         }
      }

      internal function invalidate() : void
      {
         this.session = null;
      }
   }
}
