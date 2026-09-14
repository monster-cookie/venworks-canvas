package
{
   public final class CanvasHtmlComposer
   {
      private var result:CanvasHtmlLoadResult;

      private var documents:Object;

      private var templates:Object;

      private var generatedNodes:int;

      private var compositionWork:int;

      private var failure:CanvasHtmlDiagnostic;

      private var activeState:String;

      public function compose(param1:CanvasHtmlLoadResult, param2:Object, param3:String = null) : CanvasHtmlComposeResult
      {
         this.result = param1;
         this.documents = {};
         this.templates = {};
         this.generatedNodes = 0;
         this.compositionWork = 0;
         this.failure = null;
         this.activeState = param3;
         if(param1 == null || !param1.success || param1.entryDocument == null)
         {
            return new CanvasHtmlComposeResult(false,null,new CanvasHtmlDiagnostic("compose","missing-document",null));
         }
         var resource:CanvasHtmlResource = null;
         for each(resource in param1.resources)
         {
            if(resource.document != null)
            {
               this.documents[resource.path] = resource.document;
            }
         }
         if(!this.collectTemplates())
         {
            return new CanvasHtmlComposeResult(false,null,this.failure);
         }
         var body:CanvasHtmlNode = this.getBody(param1.entryDocument);
         if(body == null)
         {
            return new CanvasHtmlComposeResult(false,null,new CanvasHtmlDiagnostic("compose","missing-body",param1.entryDocument.resource));
         }
         var output:CanvasHtmlNode = this.cloneElement(param1.entryDocument.root);
         output.children = [];
         var outputBody:CanvasHtmlNode = this.cloneElement(body);
         outputBody.children = [];
         output.children.push(outputBody);
         this.generatedNodes = 2;
         var rootScope:Object = {"values":param2 == null ? {} : param2,"parent":null};
         var frames:Array = [];
         this.pushChildren(frames,body.children,outputBody,rootScope,3,[],body.resource);
         while(frames.length > 0 && this.failure == null)
         {
            var frame:Object = frames.pop();
            if(!this.consumeWork(String(frame.resource)))
            {
               break;
            }
            this.expand(frame,frames);
         }
         if(this.failure != null)
         {
            return new CanvasHtmlComposeResult(false,null,this.failure);
         }
         return new CanvasHtmlComposeResult(true,output,null);
      }

      private function collectTemplates() : Boolean
      {
         var resource:CanvasHtmlResource = null;
         for each(resource in this.result.resources)
         {
            if(resource.document == null || resource.document.root == null)
            {
               continue;
            }
            var nodes:Array = [];
            if(!this.pushTemplateNode(nodes,resource.document.root,resource.path))
            {
               return false;
            }
            while(nodes.length > 0 && this.failure == null)
            {
               var node:CanvasHtmlNode = nodes.pop() as CanvasHtmlNode;
               if(!this.consumeWork(node.resource))
               {
                  return false;
               }
               if(node.type == CanvasHtmlNode.ELEMENT && node.name == "template")
               {
                  var identifier:String = node.getAttribute("id");
                  if(this.templates.hasOwnProperty(identifier))
                  {
                     return this.reject("duplicate-template",node.resource);
                  }
                  this.templates[identifier] = node;
               }
               for(var index:int = node.children.length - 1; index >= 0; index--)
               {
                  if(!this.pushTemplateNode(nodes,node.children[index] as CanvasHtmlNode,node.resource))
                  {
                     return false;
                  }
               }
            }
         }
         return true;
      }

      private function expand(param1:Object, param2:Array) : void
      {
         var source:CanvasHtmlNode = param1.source as CanvasHtmlNode;
         if(source == null)
         {
            this.reject("adapter-failure",String(param1.resource),"lifecycle");
            return;
         }
         if(source.type == CanvasHtmlNode.TEXT)
         {
            var normalized:String = this.normalizeText(source.text);
            if(normalized.length > 0)
            {
               var textNode:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.TEXT,source.offset);
               textNode.text = normalized;
               textNode.resource = source.resource;
               this.appendNode(param1.parent as CanvasHtmlNode,textNode,int(param1.depth));
            }
            return;
         }
         var scope:Object = param1.scope;
         if(source.name == "template")
         {
            return;
         }
         if(source.name == "vw-include")
         {
            var includePath:String = CanvasHtmlPath.resolve(String(param1.resource),source.getAttribute("src"));
            var includeDocument:CanvasHtmlDocument = includePath == null ? null : this.documents[includePath] as CanvasHtmlDocument;
            var includeBody:CanvasHtmlNode = this.getBody(includeDocument);
            if(includeBody == null)
            {
               this.reject("resource-unavailable",String(param1.resource),"asset");
               return;
            }
            this.pushChildren(param2,includeBody.children,param1.parent as CanvasHtmlNode,scope,int(param1.depth),param1.templateChain as Array,includePath);
            return;
         }
         if(source.name == "vw-use")
         {
            var templateId:String = source.getAttribute("template").substr(1);
            var templateNode:CanvasHtmlNode = this.templates[templateId] as CanvasHtmlNode;
            if(templateNode == null)
            {
               this.reject("missing-template",String(param1.resource));
               return;
            }
            var chain:Array = param1.templateChain as Array;
            if(chain.indexOf(templateId) >= 0)
            {
               this.reject("template-cycle",String(param1.resource));
               return;
            }
            this.pushChildren(param2,templateNode.children,param1.parent as CanvasHtmlNode,scope,int(param1.depth),chain.concat([templateId]),templateNode.resource);
            return;
         }
         if(source.name == "vw-state")
         {
            var stateName:String = source.getAttribute("name");
            if(stateName != null)
            {
               if(stateName == this.activeState)
               {
                  this.pushChildren(param2,source.children,param1.parent as CanvasHtmlNode,scope,int(param1.depth),param1.templateChain as Array,String(param1.resource));
               }
               return;
            }
            var stateValue:Object = CanvasHtmlData.resolve(scope,source.getAttribute("when"));
            if(stateValue.found && typeof stateValue.value != "boolean")
            {
               this.reject("invalid-binding",String(param1.resource));
               return;
            }
            if(stateValue.found && stateValue.value === true)
            {
               this.pushChildren(param2,source.children,param1.parent as CanvasHtmlNode,scope,int(param1.depth),param1.templateChain as Array,String(param1.resource));
            }
            return;
         }
         if(source.name == "vw-repeat")
         {
            var repeatValue:Object = CanvasHtmlData.resolve(scope,source.getAttribute("items"));
            if(!repeatValue.found)
            {
               return;
            }
            if(!(repeatValue.value is Array) || (repeatValue.value as Array).length > CanvasHtmlLimits.MAX_REPEAT_ITEMS)
            {
               this.reject("invalid-binding",String(param1.resource));
               return;
            }
            var items:Array = repeatValue.value as Array;
            for(var itemIndex:int = items.length - 1; itemIndex >= 0; itemIndex--)
            {
               if(!this.consumeWork(String(param1.resource)))
               {
                  return;
               }
               var item:* = items[itemIndex];
               var local:Object = item != null && typeof item == "object" && !(item is Array) ? item : {"item":item};
               this.pushChildren(param2,source.children,param1.parent as CanvasHtmlNode,{"values":local,"parent":scope},int(param1.depth),param1.templateChain as Array,String(param1.resource));
            }
            return;
         }
         var visibleName:String = source.getAttribute("data-vw-visible");
         if(visibleName != null)
         {
            var visibleValue:Object = CanvasHtmlData.resolve(scope,visibleName);
            if(visibleValue.found && typeof visibleValue.value != "boolean")
            {
               this.reject("invalid-binding",String(param1.resource));
               return;
            }
            if(!visibleValue.found || visibleValue.value !== true)
            {
               return;
            }
         }
         var output:CanvasHtmlNode = this.cloneElement(source);
         if(source.name == "vw-meter")
         {
            var meterValue:Object = CanvasHtmlData.resolve(scope,source.getAttribute("value"));
            if(meterValue.found && (typeof meterValue.value != "number" || !isFinite(Number(meterValue.value))))
            {
               this.reject("invalid-binding",String(param1.resource));
               return;
            }
            output.bindingValue = meterValue.found ? meterValue.value : 0;
         }
         if(!this.appendNode(param1.parent as CanvasHtmlNode,output,int(param1.depth)))
         {
            return;
         }
         var template:String = source.getAttribute("data-vw-template");
         var textName:String = source.getAttribute("data-vw-text");
         if(template != null || textName != null)
         {
            var boundText:String = "";
            try
            {
               if(template != null)
               {
                  boundText = CanvasHtmlData.formatTemplate(template,scope);
               }
               else
               {
                  var textValue:Object = CanvasHtmlData.resolve(scope,textName);
                  boundText = textValue.found ? CanvasHtmlData.toText(textValue.value) : "";
                  var format:String = source.getAttribute("data-vw-format");
                  if(format != null)
                  {
                     boundText = CanvasHtmlData.formatText(format,boundText);
                  }
               }
            }
            catch(textError:*)
            {
               this.reject("invalid-binding",String(param1.resource));
               return;
            }
            if(boundText.length > 0)
            {
               var boundNode:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.TEXT,source.offset);
               boundNode.text = boundText;
               boundNode.resource = source.resource;
               this.appendNode(output,boundNode,int(param1.depth) + 1);
            }
         }
         else if(source.name != "img" && source.name != "vw-meter")
         {
            this.pushChildren(param2,source.children,output,scope,int(param1.depth) + 1,param1.templateChain as Array,String(param1.resource));
         }
      }

      private function pushChildren(param1:Array, param2:Array, param3:CanvasHtmlNode, param4:Object, param5:int, param6:Array, param7:String) : void
      {
         for(var index:int = param2.length - 1; index >= 0 && this.failure == null; index--)
         {
            if(!this.consumeWork(param7))
            {
               return;
            }
            param1.push({"source":param2[index],"parent":param3,"scope":param4,"depth":param5,"templateChain":param6,"resource":param7});
         }
      }

      private function pushTemplateNode(param1:Array, param2:CanvasHtmlNode, param3:String) : Boolean
      {
         if(param2 == null)
         {
            return this.reject("adapter-failure",param3,"lifecycle");
         }
         if(!this.consumeWork(param3))
         {
            return false;
         }
         param1.push(param2);
         return true;
      }

      private function consumeWork(param1:String) : Boolean
      {
         if(this.compositionWork >= CanvasHtmlLimits.MAX_COMPOSITION_WORK)
         {
            return this.reject("limit-exceeded",param1,"compose","composition-work");
         }
         this.compositionWork++;
         return true;
      }

      private function appendNode(param1:CanvasHtmlNode, param2:CanvasHtmlNode, param3:int) : Boolean
      {
         this.generatedNodes++;
         if(this.generatedNodes > CanvasHtmlLimits.MAX_GENERATED_NODES || param3 > CanvasHtmlLimits.MAX_DOM_DEPTH)
         {
            return this.reject("limit-exceeded",param2.resource,"compose",this.generatedNodes > CanvasHtmlLimits.MAX_GENERATED_NODES ? "generated-node-count" : "generated-depth");
         }
         param1.children.push(param2);
         return true;
      }

      private function cloneElement(param1:CanvasHtmlNode) : CanvasHtmlNode
      {
         var clone:CanvasHtmlNode = new CanvasHtmlNode(param1.type,param1.offset);
         clone.name = param1.name;
         clone.text = param1.text;
         clone.attributes = param1.attributes.concat();
         clone.resource = param1.resource;
         clone.referenceOffset = param1.referenceOffset;
         clone.bindingValue = param1.bindingValue;
         return clone;
      }

      private function getBody(param1:CanvasHtmlDocument) : CanvasHtmlNode
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

      private function normalizeText(param1:String) : String
      {
         if(param1 == null || /^\s*$/.test(param1))
         {
            return "";
         }
         return param1.replace(/\s+/g," ");
      }

      private function reject(param1:String, param2:String, param3:String = "compose", param4:String = null) : Boolean
      {
         if(this.failure == null)
         {
            this.failure = new CanvasHtmlDiagnostic(param3,param1,param2,-1,param4);
         }
         return false;
      }
   }
}
