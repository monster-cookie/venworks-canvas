package
{
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLLoader;
   import flash.net.URLLoaderDataFormat;
   import flash.net.URLRequest;
   import flash.utils.ByteArray;

   public final class CanvasHtmlDocumentLoader
   {
      private var activeLoader:URLLoader;

      private var activeItem:Object;

      private var pending:Array = [];

      private var resources:Array = [];

      private var scheduled:Object = {};

      private var documentsByPath:Object = {};

      private var entryPath:String;

      private var entryDocument:CanvasHtmlDocument;

      private var aggregateBytes:int;

      private var includeCount:int;

      private var stylesheetCount:int;

      private var callback:Function;

      private var active:Boolean;

      private var disposed:Boolean;

      private var resourceRoot:String;

      private var attemptGeneration:int;

      public function CanvasHtmlDocumentLoader(param1:String)
      {
         if(!CanvasHtmlPath.isValidNamespace(param1))
         {
            throw new Error("Canvas HTML loader requires a valid consumer namespace");
         }
         this.resourceRoot = "VenworksCanvas/Consumers/" + param1 + "/";
      }

      public function get isActive() : Boolean
      {
         return this.active;
      }

      public function load(param1:String, param2:Function) : void
      {
         if(this.disposed)
         {
            throw new Error("Canvas HTML loader is disposed");
         }
         if(this.active)
         {
            throw new Error("Canvas HTML loader already has an active request");
         }
         if(param2 == null)
         {
            throw new Error("Canvas HTML loader requires a completion callback");
         }
         this.attemptGeneration++;
         if(this.attemptGeneration < 1)
         {
            this.attemptGeneration = 1;
         }
         this.resetAttempt();
         this.callback = param2;
         this.entryPath = param1;
         this.active = true;
         if(!CanvasHtmlPath.isValid(param1,".html"))
         {
            this.finishFailure(new CanvasHtmlDiagnostic("load","invalid-path",param1));
            return;
         }
         this.scheduled[param1] = true;
         this.pending.push({"path":param1,"includeDepth":0,"includeChain":[param1]});
         this.startNext();
      }

      public function cancel() : void
      {
         if(!this.active)
         {
            return;
         }
         var resource:String = this.activeItem == null ? this.entryPath : String(this.activeItem.path);
         this.abortActiveLoader();
         this.finishFailure(new CanvasHtmlDiagnostic("load","cancelled",resource),true);
      }

      public function dispose() : void
      {
         if(this.disposed)
         {
            return;
         }
         this.disposed = true;
         this.abortActiveLoader();
         this.active = false;
         this.callback = null;
         this.resetAttempt();
      }

      private function startNext() : void
      {
         if(!this.active || this.disposed)
         {
            return;
         }
         if(this.pending.length == 0)
         {
            var graphFailure:CanvasHtmlDiagnostic = this.validateIncludeGraph();
            if(graphFailure != null)
            {
               this.finishFailure(graphFailure);
               return;
            }
            this.finishSuccess();
            return;
         }
         this.activeItem = this.pending.shift();
         var loader:URLLoader = new URLLoader();
         loader.dataFormat = URLLoaderDataFormat.BINARY;
         loader.addEventListener(Event.COMPLETE,this.onLoadComplete,false,0,true);
         loader.addEventListener(IOErrorEvent.IO_ERROR,this.onLoadError,false,0,true);
         loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onLoadSecurityError,false,0,true);
         this.activeLoader = loader;
         try
         {
            loader.load(new URLRequest(this.resourceRoot + String(this.activeItem.path)));
         }
         catch(loadError:*)
         {
            var failedPath:String = String(this.activeItem.path);
            this.abortActiveLoader();
            this.finishFailure(new CanvasHtmlDiagnostic("load","resource-unavailable",failedPath));
         }
      }

      private function onLoadComplete(param1:Event) : void
      {
         if(!this.isCurrentEvent(param1))
         {
            return;
         }
         var loader:URLLoader = this.activeLoader;
         var item:Object = this.activeItem;
         var generation:int = this.attemptGeneration;
         this.detachLoader(loader);
         this.activeLoader = null;
         this.activeItem = null;
         try
         {
            var bytes:ByteArray = loader.data as ByteArray;
            if(bytes == null)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","resource-unavailable",String(item.path)));
               return;
            }
            if(bytes.length > CanvasHtmlLimits.MAX_SOURCE_BYTES)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",String(item.path),-1,"source-file-bytes"));
               return;
            }
            if(this.aggregateBytes + bytes.length > CanvasHtmlLimits.MAX_AGGREGATE_BYTES)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",String(item.path),-1,"aggregate-loaded-bytes"));
               return;
            }
            var decoded:CanvasUtf8Result = CanvasUtf8Decoder.decode(bytes);
            if(!decoded.success)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","invalid-encoding",String(item.path),decoded.errorOffset));
               return;
            }
            this.aggregateBytes += bytes.length;
            var extension:String = CanvasHtmlPath.getExtension(String(item.path));
            var document:CanvasHtmlDocument = null;
            if(extension == ".html")
            {
               var parsed:CanvasHtmlParseResult = new CanvasHtmlParser().parse(decoded.text,String(item.path));
               if(!parsed.success)
               {
                  this.finishFailure(parsed.diagnostic);
                  return;
               }
               document = parsed.document;
               this.documentsByPath[String(item.path)] = document;
               this.stylesheetCount += document.inlineStyleCount;
               if(this.stylesheetCount > CanvasHtmlLimits.MAX_STYLESHEETS)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("style","limit-exceeded",String(item.path),-1,"stylesheet-count"));
                  return;
               }
            }
            var resource:CanvasHtmlResource = new CanvasHtmlResource(String(item.path),extension.substr(1),decoded.text,bytes.length,document);
            this.resources.push(resource);
            if(String(item.path) == this.entryPath)
            {
               this.entryDocument = document;
            }
            if(document != null && !this.scheduleReferences(item,document.references))
            {
               return;
            }
            this.startNext();
         }
         catch(processError:*)
         {
            if(!this.active || this.disposed || this.attemptGeneration != generation)
            {
               throw processError;
            }
            this.finishFailure(new CanvasHtmlDiagnostic("lifecycle","adapter-failure",String(item.path)));
         }
      }

      private function scheduleReferences(param1:Object, param2:Array) : Boolean
      {
         var candidates:Array = [];
         var reference:CanvasHtmlReference = null;
         var resolved:String = null;
         var expectedExtension:String = null;
         var depth:int = 0;
         var chain:Array = null;
         for each(reference in param2)
         {
            resolved = CanvasHtmlPath.resolve(String(param1.path),reference.path);
            expectedExtension = reference.kind == CanvasHtmlReference.INCLUDE ? ".html" : reference.kind == CanvasHtmlReference.STYLESHEET ? ".css" : ".svg";
            if(resolved == null || CanvasHtmlPath.getExtension(resolved) != expectedExtension)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-path",String(param1.path),reference.offset));
               return false;
            }
            depth = int(param1.includeDepth);
            chain = param1.includeChain as Array;
            if(reference.kind == CanvasHtmlReference.INCLUDE)
            {
               this.includeCount++;
               depth++;
               if(chain.indexOf(resolved) >= 0)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("compose","cycle",String(param1.path),reference.offset));
                  return false;
               }
               if(depth > CanvasHtmlLimits.MAX_INCLUDE_DEPTH)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("compose","limit-exceeded",String(param1.path),reference.offset,"include-depth"));
                  return false;
               }
               if(this.includeCount > CanvasHtmlLimits.MAX_INCLUDE_COUNT)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("compose","limit-exceeded",String(param1.path),reference.offset,"include-count"));
                  return false;
               }
               chain = chain.concat([resolved]);
            }
            if(this.scheduled.hasOwnProperty(resolved))
            {
               continue;
            }
            if(this.resources.length + this.pending.length + candidates.length >= CanvasHtmlLimits.MAX_RESOURCES)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",resolved,-1,"resource-count"));
               return false;
            }
            if(reference.kind == CanvasHtmlReference.STYLESHEET)
            {
               this.stylesheetCount++;
               if(this.stylesheetCount > CanvasHtmlLimits.MAX_STYLESHEETS)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("style","limit-exceeded",resolved,-1,"stylesheet-count"));
                  return false;
               }
            }
            this.scheduled[resolved] = true;
            candidates.push({"path":resolved,"includeDepth":depth,"includeChain":chain});
         }
         for(var index:int = candidates.length - 1; index >= 0; index--)
         {
            this.pending.unshift(candidates[index]);
         }
         return true;
      }

      private function validateIncludeGraph() : CanvasHtmlDiagnostic
      {
         var frames:Array = [{"path":this.entryPath,"depth":0,"chain":[this.entryPath],"referenceIndex":0}];
         var expansions:int = 0;
         while(frames.length > 0)
         {
            var frame:Object = frames[frames.length - 1];
            var document:CanvasHtmlDocument = this.documentsByPath[String(frame.path)] as CanvasHtmlDocument;
            if(document == null)
            {
               return new CanvasHtmlDiagnostic("load","resource-unavailable",String(frame.path));
            }
            var reference:CanvasHtmlReference = null;
            while(int(frame.referenceIndex) < document.references.length)
            {
               reference = document.references[int(frame.referenceIndex)] as CanvasHtmlReference;
               frame.referenceIndex = int(frame.referenceIndex) + 1;
               if(reference.kind == CanvasHtmlReference.INCLUDE)
               {
                  break;
               }
               reference = null;
            }
            if(reference == null)
            {
               frames.pop();
               continue;
            }
            var resolved:String = CanvasHtmlPath.resolve(String(frame.path),reference.path);
            if(resolved == null)
            {
               return new CanvasHtmlDiagnostic("asset","invalid-path",String(frame.path),reference.offset);
            }
            var chain:Array = frame.chain as Array;
            if(chain.indexOf(resolved) >= 0)
            {
               return new CanvasHtmlDiagnostic("compose","cycle",String(frame.path),reference.offset);
            }
            var depth:int = int(frame.depth) + 1;
            if(depth > CanvasHtmlLimits.MAX_INCLUDE_DEPTH)
            {
               return new CanvasHtmlDiagnostic("compose","limit-exceeded",String(frame.path),reference.offset,"include-depth");
            }
            expansions++;
            if(expansions > CanvasHtmlLimits.MAX_INCLUDE_COUNT)
            {
               return new CanvasHtmlDiagnostic("compose","limit-exceeded",String(frame.path),reference.offset,"include-count");
            }
            frames.push({"path":resolved,"depth":depth,"chain":chain.concat([resolved]),"referenceIndex":0});
         }
         return null;
      }

      private function onLoadError(param1:IOErrorEvent) : void
      {
         this.handleResourceError(param1);
      }

      private function onLoadSecurityError(param1:SecurityErrorEvent) : void
      {
         this.handleResourceError(param1);
      }

      private function handleResourceError(param1:Event) : void
      {
         if(!this.isCurrentEvent(param1))
         {
            return;
         }
         var resource:String = String(this.activeItem.path);
         this.abortActiveLoader();
         this.finishFailure(new CanvasHtmlDiagnostic("load","resource-unavailable",resource));
      }

      private function isCurrentEvent(param1:Event) : Boolean
      {
         return this.active && !this.disposed && this.activeLoader != null && param1.currentTarget === this.activeLoader;
      }

      private function finishSuccess() : void
      {
         if(!this.active)
         {
            return;
         }
         var result:CanvasHtmlLoadResult = new CanvasHtmlLoadResult(true,false,this.entryDocument,this.resources.concat(),null);
         this.publish(result);
      }

      private function finishFailure(param1:CanvasHtmlDiagnostic, param2:Boolean = false) : void
      {
         if(!this.active)
         {
            return;
         }
         this.abortActiveLoader();
         this.pending = [];
         this.resources = [];
         this.entryDocument = null;
         this.publish(new CanvasHtmlLoadResult(false,param2,null,[],param1));
      }

      private function publish(param1:CanvasHtmlLoadResult) : void
      {
         var completion:Function = this.callback;
         this.active = false;
         this.callback = null;
         this.activeItem = null;
         if(completion != null && !this.disposed)
         {
            completion(param1);
         }
      }

      private function abortActiveLoader() : void
      {
         if(this.activeLoader == null)
         {
            this.activeItem = null;
            return;
         }
         var loader:URLLoader = this.activeLoader;
         this.detachLoader(loader);
         this.activeLoader = null;
         this.activeItem = null;
         try
         {
            loader.close();
         }
         catch(closeError:*)
         {
         }
      }

      private function detachLoader(param1:URLLoader) : void
      {
         param1.removeEventListener(Event.COMPLETE,this.onLoadComplete);
         param1.removeEventListener(IOErrorEvent.IO_ERROR,this.onLoadError);
         param1.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onLoadSecurityError);
      }

      private function resetAttempt() : void
      {
         this.pending = [];
         this.resources = [];
         this.scheduled = {};
         this.documentsByPath = {};
         this.entryPath = null;
         this.entryDocument = null;
         this.aggregateBytes = 0;
         this.includeCount = 0;
         this.stylesheetCount = 0;
         this.activeItem = null;
      }
   }
}
