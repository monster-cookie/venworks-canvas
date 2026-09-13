package
{
   import flash.display.DisplayObjectContainer;

   public final class CanvasHtmlEngine
   {
      private var consumers:Object = {};

      private var disposed:Boolean;

      public function CanvasHtmlEngine()
      {
      }

      public function load(param1:String, param2:String, param3:Object, param4:DisplayObjectContainer, param5:Function) : void
      {
         if(this.disposed)
         {
            throw new Error("Canvas HTML engine is disposed");
         }
         if(param1 == null || param1.length == 0 || this.consumers[param1] != null)
         {
            throw new Error("Canvas HTML engine requires one unique consumer load");
         }
         if(param4 == null)
         {
            throw new Error("Canvas HTML engine requires a display mount");
         }
         if(param5 == null)
         {
            throw new Error("Canvas HTML engine requires a completion callback");
         }
         var registration:Object = this.validateRegistration(param2,param3);
         var loader:CanvasHtmlDocumentLoader = new CanvasHtmlDocumentLoader(param2);
         var entry:Object = {
            "loader":loader,
            "registration":registration,
            "mount":param4,
            "callback":param5,
            "result":null,
            "session":null,
            "bridge":null
         };
         this.consumers[param1] = entry;
         var owner:CanvasHtmlEngine = this;
         try
         {
            loader.load(String(registration.entryDocument),function(param5:CanvasHtmlLoadResult):void
            {
               owner.finish(param1,entry,param5);
            });
         }
         catch(loadError:*)
         {
            if(this.consumers[param1] === entry)
            {
               delete this.consumers[param1];
            }
            loader.dispose();
            throw loadError;
         }
      }

      public function remove(param1:String) : void
      {
         var entry:Object = this.consumers[param1];
         if(entry == null)
         {
            return;
         }
         delete this.consumers[param1];
         entry.callback = null;
         var bridge:CanvasHtmlBridge = entry.bridge as CanvasHtmlBridge;
         entry.bridge = null;
         if(bridge != null)
         {
            bridge.invalidate();
         }
         var session:CanvasHtmlSession = entry.session as CanvasHtmlSession;
         entry.session = null;
         if(session != null)
         {
            session.dispose();
         }
         var loader:CanvasHtmlDocumentLoader = entry.loader as CanvasHtmlDocumentLoader;
         entry.loader = null;
         entry.result = null;
         entry.mount = null;
         if(loader != null)
         {
            loader.dispose();
         }
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         var consumerIds:Array = [];
         var consumerId:String = null;
         for(consumerId in this.consumers)
         {
            consumerIds.push(consumerId);
         }
         for each(consumerId in consumerIds)
         {
            this.remove(consumerId);
         }
         this.consumers = {};
      }

      public function getBridge(param1:String) : Object
      {
         var entry:Object = this.consumers[param1];
         return this.disposed || entry == null ? null : entry.bridge;
      }

      private function validateRegistration(param1:String, param2:Object) : Object
      {
         if(!CanvasHtmlPath.isValidNamespace(param1))
         {
            throw new Error("Canvas HTML registration has an invalid consumer namespace");
         }
         if(param2 == null || param2 is Array || typeof param2 != "object")
         {
            throw new Error("Canvas HTML registration must be an object");
         }
         var field:String = null;
         for(field in param2)
         {
            if(field != "contract" && field != "entryDocument")
            {
               throw new Error("Canvas HTML registration contains an unknown field");
            }
         }
         if(typeof param2.contract != "string" || param2.contract != "VWCANVAS_HTML/2")
         {
            throw new Error("Canvas HTML registration has an unsupported contract");
         }
         if(typeof param2.entryDocument != "string" || !CanvasHtmlPath.isValid(param2.entryDocument,".html"))
         {
            throw new Error("Canvas HTML registration has an invalid entry document");
         }
         return {
            "contract":"VWCANVAS_HTML/2",
            "entryDocument":String(param2.entryDocument)
         };
      }

      private function finish(param1:String, param2:Object, param3:CanvasHtmlLoadResult) : void
      {
         if(this.disposed || this.consumers[param1] !== param2)
         {
            return;
         }
         var loader:CanvasHtmlDocumentLoader = param2.loader as CanvasHtmlDocumentLoader;
         param2.loader = null;
         if(loader != null)
         {
            loader.dispose();
         }
         var finalResult:CanvasHtmlLoadResult = param3;
         if(param3.success)
         {
            try
            {
               var session:CanvasHtmlSession = new CanvasHtmlSession(param2.mount as DisplayObjectContainer,param3);
               var diagnostic:CanvasHtmlDiagnostic = session.initialize();
               if(diagnostic == null)
               {
                  param2.session = session;
                  param2.bridge = new CanvasHtmlBridge(session);
               }
               else
               {
                  session.dispose();
                  finalResult = new CanvasHtmlLoadResult(false,false,null,[],diagnostic);
               }
            }
            catch(renderError:*)
            {
               if(session != null)
               {
                  session.dispose();
               }
               finalResult = new CanvasHtmlLoadResult(false,false,null,[],new CanvasHtmlDiagnostic("lifecycle","adapter-failure",param3.entryDocument == null ? null : param3.entryDocument.resource));
            }
         }
         param2.result = finalResult.success ? finalResult : null;
         var callback:Function = param2.callback as Function;
         param2.callback = null;
         if(callback != null)
         {
            callback(param1,finalResult);
         }
         if(!finalResult.success && this.consumers[param1] === param2)
         {
            delete this.consumers[param1];
         }
      }
   }
}
