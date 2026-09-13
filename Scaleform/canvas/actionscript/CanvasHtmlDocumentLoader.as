package
{
   import flash.display.Bitmap;
   import flash.display.Loader;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.URLLoader;
   import flash.net.URLLoaderDataFormat;
   import flash.net.URLRequest;
   import flash.utils.ByteArray;
   import flash.utils.Endian;

   public final class CanvasHtmlDocumentLoader
   {
      private var activeLoader:URLLoader;

      private var activeItem:Object;

      private var activeRasterLoader:Loader;

      private var activeRasterResource:CanvasHtmlResource;

      private var activeRasterWidth:uint;

      private var activeRasterHeight:uint;

      private var activeRasterPixels:Number = 0;

      private var pending:Array = [];

      private var resources:Array = [];

      private var loadedPaths:Object = {};

      private var pendingByPath:Object = {};

      private var documentsByPath:Object = {};

      private var entryPath:String;

      private var entryDocument:CanvasHtmlDocument;

      private var aggregateBytes:int;

      private var aggregateRasterPixels:Number = 0;

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
         var entry:Object = {"path":param1};
         this.pendingByPath[param1] = entry;
         this.pending.push(entry);
         this.startNext();
      }

      public function cancel() : void
      {
         if(!this.active)
         {
            return;
         }
         var resource:String = this.activeRasterResource != null ? this.activeRasterResource.path : this.activeItem == null ? this.entryPath : String(this.activeItem.path);
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
         this.abortRasterLoader();
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
            var graphFailure:CanvasHtmlDiagnostic = this.validateComposedDocument();
            if(graphFailure != null)
            {
               this.finishFailure(graphFailure);
               return;
            }
            this.finishSuccess();
            return;
         }
         this.activeItem = this.pending.shift();
         delete this.pendingByPath[String(this.activeItem.path)];
         var loader:URLLoader = new URLLoader();
         loader.dataFormat = URLLoaderDataFormat.BINARY;
         loader.addEventListener(Event.COMPLETE,this.onLoadComplete,false,0,true);
         loader.addEventListener(ProgressEvent.PROGRESS,this.onLoadProgress,false,0,true);
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
            var extension:String = CanvasHtmlPath.getExtension(String(item.path));
            var sourceLimit:int = extension == ".png" ? CanvasHtmlLimits.MAX_RASTER_BYTES : CanvasHtmlLimits.MAX_SOURCE_BYTES;
            if(bytes.length > sourceLimit)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",String(item.path),-1,"source-file-bytes"));
               return;
            }
            if(this.aggregateBytes + bytes.length > CanvasHtmlLimits.MAX_AGGREGATE_BYTES)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",String(item.path),-1,"aggregate-loaded-bytes"));
               return;
            }
            this.aggregateBytes += bytes.length;
            if(extension == ".png")
            {
               var dimensions:Object = this.readPngDimensions(bytes);
               if(dimensions == null)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-raster",String(item.path)));
                  return;
               }
               var rasterPixels:Number = Number(dimensions.width) * Number(dimensions.height);
               if(this.aggregateRasterPixels > CanvasHtmlLimits.MAX_AGGREGATE_RASTER_PIXELS - rasterPixels)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("asset","limit-exceeded",String(item.path),-1,"aggregate-raster-pixels"));
                  return;
               }
               this.aggregateRasterPixels += rasterPixels;
               this.beginRasterDecode(String(item.path),bytes,uint(dimensions.width),uint(dimensions.height),rasterPixels);
               return;
            }
            var decoded:CanvasUtf8Result = CanvasUtf8Decoder.decode(bytes);
            if(!decoded.success)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("load","invalid-encoding",String(item.path),decoded.errorOffset));
               return;
            }
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
            this.loadedPaths[String(item.path)] = true;
            if(String(item.path) == this.entryPath)
            {
               this.entryDocument = document;
            }
            if(document != null && !this.scheduleReferences(item,document.references))
            {
               return;
            }
            var imports:CanvasCssImportResult = null;
            if(extension == ".css")
            {
               imports = new CanvasCssImportScanner().scan(decoded.text,String(item.path));
               if(!imports.success || !this.scheduleCssImports(item,imports.imports))
               {
                  if(!imports.success)
                  {
                     this.finishFailure(imports.diagnostic);
                  }
                  return;
               }
            }
            else if(document != null && !this.scheduleInlineCssImports(item,document))
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
         var candidatePaths:Object = {};
         var reference:CanvasHtmlReference = null;
         var resolved:String = null;
         var expectedExtension:String = null;
         var candidate:Object = null;
         for each(reference in param2)
         {
            resolved = CanvasHtmlPath.resolve(String(param1.path),reference.path);
            expectedExtension = reference.kind == CanvasHtmlReference.INCLUDE ? ".html" : reference.kind == CanvasHtmlReference.STYLESHEET ? ".css" : CanvasHtmlPath.getExtension(reference.path);
            if(reference.kind == CanvasHtmlReference.IMAGE && expectedExtension != ".svg" && expectedExtension != ".png")
            {
               expectedExtension = null;
            }
            if(resolved == null || CanvasHtmlPath.getExtension(resolved) != expectedExtension)
            {
               this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-path",String(param1.path),reference.offset));
               return false;
            }
            if(this.loadedPaths.hasOwnProperty(resolved) || candidatePaths.hasOwnProperty(resolved))
            {
               continue;
            }
            candidate = this.takePending(resolved);
            if(candidate == null)
            {
               if(this.resources.length + this.pending.length + candidates.length >= CanvasHtmlLimits.MAX_RESOURCES)
               {
                  this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",resolved,-1,"resource-count"));
                  return false;
               }
               candidate = {"path":resolved};
               if(reference.kind == CanvasHtmlReference.STYLESHEET)
               {
                  this.stylesheetCount++;
                  if(this.stylesheetCount > CanvasHtmlLimits.MAX_STYLESHEETS)
                  {
                     this.finishFailure(new CanvasHtmlDiagnostic("style","limit-exceeded",resolved,-1,"stylesheet-count"));
                     return false;
                  }
               }
            }
            candidatePaths[resolved] = true;
            candidates.push(candidate);
         }
         for(var index:int = candidates.length - 1; index >= 0; index--)
         {
            this.pendingByPath[String(candidates[index].path)] = candidates[index];
            this.pending.unshift(candidates[index]);
         }
         return true;
      }

      private function scheduleCssImports(param1:Object, param2:Array) : Boolean
      {
         var references:Array = [];
         var imported:Object = null;
         for each(imported in param2)
         {
            references.push(new CanvasHtmlReference(CanvasHtmlReference.STYLESHEET,String(imported.path),int(imported.byteOffset)));
         }
         return this.scheduleReferences(param1,references);
      }

      private function scheduleInlineCssImports(param1:Object, param2:CanvasHtmlDocument) : Boolean
      {
         var head:CanvasHtmlNode = null;
         var child:CanvasHtmlNode = null;
         for each(child in param2.root.children)
         {
            if(child.type == CanvasHtmlNode.ELEMENT && child.name == "head")
            {
               head = child;
               break;
            }
         }
         if(head == null)
         {
            return true;
         }
         for each(child in head.children)
         {
            if(child.name != "style")
            {
               continue;
            }
            var styleText:String = child.children.length == 0 ? "" : CanvasHtmlNode(child.children[0]).text;
            var imports:CanvasCssImportResult = new CanvasCssImportScanner().scan(styleText,String(param1.path));
            if(!imports.success)
            {
               this.finishFailure(imports.diagnostic);
               return false;
            }
            if(!this.scheduleCssImports(param1,imports.imports))
            {
               return false;
            }
         }
         return true;
      }

      private function takePending(param1:String) : Object
      {
         if(!this.pendingByPath.hasOwnProperty(param1))
         {
            return null;
         }
         var candidate:Object = this.pendingByPath[param1];
         delete this.pendingByPath[param1];
         for(var index:int = 0; index < this.pending.length; index++)
         {
            if(this.pending[index] === candidate)
            {
               this.pending.splice(index,1);
               break;
            }
         }
         return candidate;
      }

      private function validateComposedDocument() : CanvasHtmlDiagnostic
      {
         if(this.entryDocument == null || this.entryDocument.root == null)
         {
            return new CanvasHtmlDiagnostic("load","resource-unavailable",this.entryPath);
         }
         var frames:Array = [{"node":this.entryDocument.root,"depth":1,"resource":this.entryPath,"includeDepth":0,"chain":[this.entryPath],"causeResource":null,"causeOffset":-1}];
         var expandedNodes:int = 0;
         var includeExpansions:int = 0;
         while(frames.length > 0)
         {
            var frame:Object = frames.pop();
            var node:CanvasHtmlNode = frame.node as CanvasHtmlNode;
            if(node == null)
            {
               return new CanvasHtmlDiagnostic("lifecycle","adapter-failure",String(frame.resource));
            }
            if(node.type == CanvasHtmlNode.ELEMENT && node.name == "vw-include")
            {
               var resolved:String = CanvasHtmlPath.resolve(String(frame.resource),node.getAttribute("src"));
               if(resolved == null)
               {
                  return new CanvasHtmlDiagnostic("asset","invalid-path",String(frame.resource),node.referenceOffset);
               }
               var chain:Array = frame.chain as Array;
               if(chain.indexOf(resolved) >= 0)
               {
                  return new CanvasHtmlDiagnostic("compose","cycle",String(frame.resource),node.referenceOffset);
               }
               var includeDepth:int = int(frame.includeDepth) + 1;
               if(includeDepth > CanvasHtmlLimits.MAX_INCLUDE_DEPTH)
               {
                  return new CanvasHtmlDiagnostic("compose","limit-exceeded",String(frame.resource),node.referenceOffset,"include-depth");
               }
               includeExpansions++;
               if(includeExpansions > CanvasHtmlLimits.MAX_INCLUDE_COUNT)
               {
                  return new CanvasHtmlDiagnostic("compose","limit-exceeded",String(frame.resource),node.referenceOffset,"include-count");
               }
               var includedDocument:CanvasHtmlDocument = this.documentsByPath[resolved] as CanvasHtmlDocument;
               var body:CanvasHtmlNode = this.getDocumentBody(includedDocument);
               if(body == null)
               {
                  return new CanvasHtmlDiagnostic("load","resource-unavailable",resolved);
               }
               var includedChain:Array = chain.concat([resolved]);
               for(var includedIndex:int = body.children.length - 1; includedIndex >= 0; includedIndex--)
               {
                  frames.push({"node":body.children[includedIndex],"depth":frame.depth,"resource":resolved,"includeDepth":includeDepth,"chain":includedChain,"causeResource":frame.resource,"causeOffset":node.referenceOffset});
               }
               continue;
            }
            expandedNodes++;
            if(expandedNodes > CanvasHtmlLimits.MAX_DOM_NODES)
            {
               return new CanvasHtmlDiagnostic("compose","limit-exceeded",frame.causeResource == null ? String(frame.resource) : String(frame.causeResource),int(frame.causeOffset),"expanded-dom-nodes");
            }
            if(int(frame.depth) > CanvasHtmlLimits.MAX_DOM_DEPTH)
            {
               return new CanvasHtmlDiagnostic("compose","limit-exceeded",frame.causeResource == null ? String(frame.resource) : String(frame.causeResource),int(frame.causeOffset),"dom-depth");
            }
            for(var childIndex:int = node.children.length - 1; childIndex >= 0; childIndex--)
            {
               frames.push({"node":node.children[childIndex],"depth":int(frame.depth) + 1,"resource":frame.resource,"includeDepth":frame.includeDepth,"chain":frame.chain,"causeResource":frame.causeResource,"causeOffset":frame.causeOffset});
            }
         }
         return null;
      }

      private function getDocumentBody(param1:CanvasHtmlDocument) : CanvasHtmlNode
      {
         if(param1 == null || param1.root == null)
         {
            return null;
         }
         var child:CanvasHtmlNode = null;
         for each(child in param1.root.children)
         {
            if(child.type == CanvasHtmlNode.ELEMENT && child.name == "body")
            {
               return child;
            }
         }
         return null;
      }

      private function onLoadError(param1:IOErrorEvent) : void
      {
         this.handleResourceError(param1);
      }

      private function onLoadProgress(param1:ProgressEvent) : void
      {
         if(!this.isCurrentEvent(param1))
         {
            return;
         }
         var observedBytes:Number = param1.bytesLoaded;
         if(param1.bytesTotal > observedBytes)
         {
            observedBytes = param1.bytesTotal;
         }
         var resource:String = String(this.activeItem.path);
         var sourceLimit:int = CanvasHtmlPath.getExtension(resource) == ".png" ? CanvasHtmlLimits.MAX_RASTER_BYTES : CanvasHtmlLimits.MAX_SOURCE_BYTES;
         if(observedBytes > sourceLimit)
         {
            this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",resource,-1,"source-file-bytes"));
            return;
         }
         if(Number(this.aggregateBytes) + observedBytes > CanvasHtmlLimits.MAX_AGGREGATE_BYTES)
         {
            this.finishFailure(new CanvasHtmlDiagnostic("load","limit-exceeded",resource,-1,"aggregate-loaded-bytes"));
         }
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
         var publishedResources:Array = this.resources.concat();
         this.resources = [];
         var result:CanvasHtmlLoadResult = new CanvasHtmlLoadResult(true,false,this.entryDocument,publishedResources,null);
         this.publish(result);
      }

      private function finishFailure(param1:CanvasHtmlDiagnostic, param2:Boolean = false) : void
      {
         if(!this.active)
         {
            return;
         }
         this.abortActiveLoader();
         this.abortRasterLoader();
         this.pending = [];
         this.disposeResources();
         this.resources = [];
         this.aggregateRasterPixels = 0;
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

      private function beginRasterDecode(param1:String, param2:ByteArray, param3:uint, param4:uint, param5:Number) : void
      {
         var loader:Loader = new Loader();
         loader.contentLoaderInfo.addEventListener(Event.COMPLETE,this.onRasterComplete,false,0,true);
         loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,this.onRasterError,false,0,true);
         loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onRasterError,false,0,true);
         this.activeRasterLoader = loader;
         this.activeRasterResource = new CanvasHtmlResource(param1,"png",null,param2.length);
         this.activeRasterWidth = param3;
         this.activeRasterHeight = param4;
         this.activeRasterPixels = param5;
         try
         {
            param2.position = 0;
            loader.loadBytes(param2);
         }
         catch(loadError:*)
         {
            this.abortRasterLoader();
            this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-raster",param1));
         }
      }

      private function onRasterComplete(param1:Event) : void
      {
         if(!this.isCurrentRasterEvent(param1))
         {
            return;
         }
         var loader:Loader = this.activeRasterLoader;
         var resource:CanvasHtmlResource = this.activeRasterResource;
         var expectedWidth:uint = this.activeRasterWidth;
         var expectedHeight:uint = this.activeRasterHeight;
         var reservedPixels:Number = this.activeRasterPixels;
         var bitmap:Bitmap = loader.content as Bitmap;
         this.detachRasterLoader(loader);
         this.activeRasterLoader = null;
         this.activeRasterResource = null;
         this.activeRasterWidth = 0;
         this.activeRasterHeight = 0;
         this.activeRasterPixels = 0;
         if(bitmap == null || bitmap.bitmapData == null || bitmap.bitmapData.width != expectedWidth || bitmap.bitmapData.height != expectedHeight || Number(bitmap.bitmapData.width) * Number(bitmap.bitmapData.height) != reservedPixels || bitmap.bitmapData.width > CanvasHtmlLimits.MAX_RASTER_DIMENSION || bitmap.bitmapData.height > CanvasHtmlLimits.MAX_RASTER_DIMENSION || reservedPixels > CanvasHtmlLimits.MAX_RASTER_PIXELS)
         {
            this.aggregateRasterPixels = Math.max(0,this.aggregateRasterPixels - reservedPixels);
            if(bitmap != null && bitmap.bitmapData != null)
            {
               bitmap.bitmapData.dispose();
            }
            this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-raster",resource.path));
            return;
         }
         resource.bitmapData = bitmap.bitmapData;
         this.resources.push(resource);
         this.loadedPaths[resource.path] = true;
         this.startNext();
      }

      private function onRasterError(param1:Event) : void
      {
         if(!this.isCurrentRasterEvent(param1))
         {
            return;
         }
         var resource:String = this.activeRasterResource == null ? this.entryPath : this.activeRasterResource.path;
         this.abortRasterLoader();
         this.finishFailure(new CanvasHtmlDiagnostic("asset","invalid-raster",resource));
      }

      private function isCurrentRasterEvent(param1:Event) : Boolean
      {
         return this.active && !this.disposed && this.activeRasterLoader != null && param1.currentTarget === this.activeRasterLoader.contentLoaderInfo;
      }

      private function abortRasterLoader() : void
      {
         if(this.activeRasterLoader == null)
         {
            this.activeRasterResource = null;
            this.aggregateRasterPixels = Math.max(0,this.aggregateRasterPixels - this.activeRasterPixels);
            this.activeRasterWidth = 0;
            this.activeRasterHeight = 0;
            this.activeRasterPixels = 0;
            return;
         }
         var loader:Loader = this.activeRasterLoader;
         this.detachRasterLoader(loader);
         this.activeRasterLoader = null;
         this.activeRasterResource = null;
         this.aggregateRasterPixels = Math.max(0,this.aggregateRasterPixels - this.activeRasterPixels);
         this.activeRasterWidth = 0;
         this.activeRasterHeight = 0;
         this.activeRasterPixels = 0;
         try
         {
            loader.close();
         }
         catch(closeError:*)
         {
         }
         try
         {
            loader.unload();
         }
         catch(unloadError:*)
         {
         }
      }

      private function detachRasterLoader(param1:Loader) : void
      {
         param1.contentLoaderInfo.removeEventListener(Event.COMPLETE,this.onRasterComplete);
         param1.contentLoaderInfo.removeEventListener(IOErrorEvent.IO_ERROR,this.onRasterError);
         param1.contentLoaderInfo.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onRasterError);
      }

      private function readPngDimensions(param1:ByteArray) : Object
      {
         if(param1 == null || param1.length < 33)
         {
            return null;
         }
         var originalPosition:uint = param1.position;
         var originalEndian:String = param1.endian;
         param1.position = 0;
         param1.endian = Endian.BIG_ENDIAN;
         var valid:Boolean = param1.readUnsignedByte() == 137 && param1.readUnsignedByte() == 80 && param1.readUnsignedByte() == 78 && param1.readUnsignedByte() == 71 && param1.readUnsignedByte() == 13 && param1.readUnsignedByte() == 10 && param1.readUnsignedByte() == 26 && param1.readUnsignedByte() == 10;
         valid = valid && param1.readUnsignedInt() == 13 && param1.readUTFBytes(4) == "IHDR";
         var width:uint = valid ? param1.readUnsignedInt() : 0;
         var height:uint = valid ? param1.readUnsignedInt() : 0;
         param1.position = originalPosition;
         param1.endian = originalEndian;
         return valid && width > 0 && height > 0 && width <= CanvasHtmlLimits.MAX_RASTER_DIMENSION && height <= CanvasHtmlLimits.MAX_RASTER_DIMENSION && Number(width) * Number(height) <= CanvasHtmlLimits.MAX_RASTER_PIXELS ? {"width":width,"height":height} : null;
      }

      private function detachLoader(param1:URLLoader) : void
      {
         param1.removeEventListener(Event.COMPLETE,this.onLoadComplete);
         param1.removeEventListener(ProgressEvent.PROGRESS,this.onLoadProgress);
         param1.removeEventListener(IOErrorEvent.IO_ERROR,this.onLoadError);
         param1.removeEventListener(SecurityErrorEvent.SECURITY_ERROR,this.onLoadSecurityError);
      }

      private function resetAttempt() : void
      {
         this.disposeResources();
         this.pending = [];
         this.resources = [];
         this.loadedPaths = {};
         this.pendingByPath = {};
         this.documentsByPath = {};
         this.entryPath = null;
         this.entryDocument = null;
         this.aggregateBytes = 0;
         this.aggregateRasterPixels = 0;
         this.stylesheetCount = 0;
         this.activeItem = null;
         this.activeRasterWidth = 0;
         this.activeRasterHeight = 0;
         this.activeRasterPixels = 0;
      }

      private function disposeResources() : void
      {
         var resource:CanvasHtmlResource = null;
         for each(resource in this.resources)
         {
            resource.dispose();
         }
      }
   }
}
