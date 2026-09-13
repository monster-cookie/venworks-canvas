package
{
   public final class CanvasHtmlParser
   {
      private var source:String;

      private var resource:String;

      private var document:CanvasHtmlDocument;

      private var stack:Array;

      private var identities:Object;

      private var failure:CanvasHtmlDiagnostic;

      public function parse(param1:String, param2:String) : CanvasHtmlParseResult
      {
         this.source = param1 == null ? "" : param1;
         this.resource = param2;
         this.document = new CanvasHtmlDocument(param2);
         this.stack = [];
         this.identities = {};
         this.failure = null;
         var tokenizer:CanvasHtmlTokenizer = new CanvasHtmlTokenizer(this.source,param2);
         var token:CanvasHtmlToken = tokenizer.nextToken();
         if(token == null || token.type != CanvasHtmlToken.DOCTYPE)
         {
            return new CanvasHtmlParseResult(false,null,tokenizer.diagnostic == null ? this.makeDiagnostic("malformed-syntax",0) : tokenizer.diagnostic);
         }
         while(this.failure == null && (token = tokenizer.nextToken()) != null)
         {
            if(token.type == CanvasHtmlToken.START_TAG)
            {
               this.acceptStartTag(token);
            }
            else if(token.type == CanvasHtmlToken.END_TAG)
            {
               this.acceptEndTag(token);
            }
            else if(token.type == CanvasHtmlToken.TEXT || token.type == CanvasHtmlToken.CHARACTER_REFERENCE)
            {
               this.acceptText(token);
            }
            else
            {
               this.reject("malformed-syntax",token.offset);
            }
         }
         if(this.failure == null && tokenizer.diagnostic != null)
         {
            this.failure = tokenizer.diagnostic;
         }
         if(this.failure == null && this.stack.length != 0)
         {
            this.reject("malformed-syntax",this.source.length);
         }
         if(this.failure == null && this.document.root == null)
         {
            this.reject("malformed-syntax",this.source.length);
         }
         if(this.failure != null)
         {
            return new CanvasHtmlParseResult(false,null,this.failure);
         }
         this.document.tokenCount = tokenizer.tokenCount;
         return new CanvasHtmlParseResult(true,this.document,null);
      }

      private function acceptStartTag(param1:CanvasHtmlToken) : void
      {
         if(!this.isKnownElement(param1.name))
         {
            this.reject("unsupported-feature",param1.offset);
            return;
         }
         if(this.stack.length == 0)
         {
            if(this.document.root != null || param1.name != "html")
            {
               this.reject("malformed-syntax",param1.offset);
               return;
            }
         }
         else if(!this.allowsChild(CanvasHtmlNode(this.stack[this.stack.length - 1]),param1.name))
         {
            this.reject("malformed-syntax",param1.offset);
            return;
         }
         if(!this.validateAttributes(param1))
         {
            return;
         }
         var depth:int = this.stack.length + 1;
         if(depth > CanvasHtmlLimits.MAX_DOM_DEPTH)
         {
            this.reject("limit-exceeded",param1.offset,"dom-depth","compose");
            return;
         }
         if(this.document.nodeCount >= CanvasHtmlLimits.MAX_DOM_NODES)
         {
            this.reject("limit-exceeded",param1.offset,"expanded-dom-nodes","compose");
            return;
         }
         var node:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.ELEMENT,param1.offset);
         node.name = param1.name;
         node.attributes = param1.attributes;
         if(this.stack.length == 0)
         {
            this.document.root = node;
         }
         else
         {
            CanvasHtmlNode(this.stack[this.stack.length - 1]).children.push(node);
         }
         this.document.nodeCount++;
         if(depth > this.document.maximumDepth)
         {
            this.document.maximumDepth = depth;
         }
         this.recordIdentityAndReferences(node);
         if(this.failure == null)
         {
            this.stack.push(node);
         }
      }

      private function acceptEndTag(param1:CanvasHtmlToken) : void
      {
         if(this.stack.length == 0)
         {
            this.reject("malformed-syntax",param1.offset);
            return;
         }
         var node:CanvasHtmlNode = this.stack[this.stack.length - 1] as CanvasHtmlNode;
         if(node.name != param1.name)
         {
            this.reject("malformed-syntax",param1.offset);
            return;
         }
         if(!this.validateClosedElement(node,param1.offset))
         {
            return;
         }
         this.stack.pop();
         if(node.name == "title" && node.children.length == 1)
         {
            this.document.title = CanvasHtmlNode(node.children[0]).text;
         }
      }

      private function acceptText(param1:CanvasHtmlToken) : void
      {
         if(param1.text == null || param1.text.length == 0)
         {
            return;
         }
         if(this.stack.length == 0)
         {
            if(this.isOnlyWhitespace(param1.text))
            {
               return;
            }
            this.reject("malformed-syntax",param1.offset);
            return;
         }
         var parent:CanvasHtmlNode = this.stack[this.stack.length - 1] as CanvasHtmlNode;
         if(!this.allowsText(parent.name))
         {
            if(this.isOnlyWhitespace(param1.text))
            {
               return;
            }
            this.reject("malformed-syntax",param1.offset);
            return;
         }
         var previous:CanvasHtmlNode = parent.children.length == 0 ? null : parent.children[parent.children.length - 1] as CanvasHtmlNode;
         if(previous != null && previous.type == CanvasHtmlNode.TEXT)
         {
            if(previous.text.length + param1.text.length > CanvasHtmlLimits.MAX_STRING_CODE_UNITS)
            {
               this.reject("limit-exceeded",param1.offset,"string-code-units");
               return;
            }
            previous.text += param1.text;
            return;
         }
         if(this.document.nodeCount >= CanvasHtmlLimits.MAX_DOM_NODES)
         {
            this.reject("limit-exceeded",param1.offset,"expanded-dom-nodes","compose");
            return;
         }
         var textNode:CanvasHtmlNode = new CanvasHtmlNode(CanvasHtmlNode.TEXT,param1.offset);
         textNode.text = param1.text;
         parent.children.push(textNode);
         this.document.nodeCount++;
      }

      private function validateAttributes(param1:CanvasHtmlToken) : Boolean
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in param1.attributes)
         {
            if(attribute.name == "style" || attribute.name.length >= 2 && attribute.name.substr(0,2) == "on")
            {
               this.reject("unsupported-feature",attribute.offset);
               return false;
            }
            if(!this.isAllowedAttribute(param1.name,attribute.name))
            {
               this.reject("unsupported-feature",attribute.offset);
               return false;
            }
            if(this.exceedsIdentifierLimit(attribute.name,attribute.value))
            {
               this.reject("limit-exceeded",attribute.offset,"identifier-length");
               return false;
            }
            if(!this.isAllowedAttributeValue(param1.name,attribute))
            {
               this.reject("invalid-value",attribute.offset);
               return false;
            }
         }
         return this.hasRequiredAttributes(param1);
      }

      private function hasRequiredAttributes(param1:CanvasHtmlToken) : Boolean
      {
         var required:Array = [];
         if(param1.name == "meta")
         {
            required = ["charset"];
         }
         else if(param1.name == "link")
         {
            required = ["rel","href"];
         }
         else if(param1.name == "template")
         {
            required = ["id"];
         }
         else if(param1.name == "img")
         {
            required = ["src","alt"];
         }
         else if(param1.name == "svg")
         {
            required = ["viewbox"];
         }
         else if(param1.name == "path")
         {
            required = ["d"];
         }
         else if(param1.name == "vw-include")
         {
            required = ["src"];
         }
         else if(param1.name == "vw-use")
         {
            required = ["template"];
         }
         else if(param1.name == "vw-repeat")
         {
            required = ["items"];
         }
         else if(param1.name == "vw-state")
         {
            required = ["when"];
         }
         else if(param1.name == "vw-meter")
         {
            required = ["value"];
         }
         var name:String = null;
         for each(name in required)
         {
            if(!this.tokenHasAttribute(param1,name))
            {
               this.reject("invalid-value",param1.offset);
               return false;
            }
         }
         return true;
      }

      private function isAllowedAttribute(param1:String, param2:String) : Boolean
      {
         if(this.isGlobalElement(param1) && this.isGlobalAttribute(param2))
         {
            return true;
         }
         if(param1 == "meta")
         {
            return param2 == "charset";
         }
         if(param1 == "link")
         {
            return param2 == "rel" || param2 == "href";
         }
         if(param1 == "template")
         {
            return param2 == "id";
         }
         if(param1 == "img")
         {
            return param2 == "src" || param2 == "alt" || param2 == "id" || param2 == "class" || param2 == "data-vw-visible";
         }
         if(param1 == "svg")
         {
            return param2 == "viewbox" || param2 == "id" || param2 == "class" || param2 == "data-vw-visible" || param2 == "width" || param2 == "height" || param2 == "x" || param2 == "y" || param2 == "fill" || param2 == "stroke" || param2 == "stroke-width" || param2 == "clip-rule" || param2 == "preserveaspectratio" || param2 == "fill-rule" || param2 == "stroke-linecap" || param2 == "stroke-linejoin" || param2 == "vector-effect";
         }
         if(param1 == "path")
         {
            return param2 == "d" || param2 == "id" || param2 == "class" || param2 == "fill" || param2 == "stroke" || param2 == "stroke-width" || param2 == "fill-rule";
         }
         if(param1 == "vw-include")
         {
            return param2 == "src";
         }
         if(param1 == "vw-use")
         {
            return param2 == "template";
         }
         if(param1 == "vw-repeat")
         {
            return param2 == "items";
         }
         if(param1 == "vw-state")
         {
            return param2 == "when";
         }
         if(param1 == "vw-meter")
         {
            return param2 == "value" || param2 == "id" || param2 == "class" || param2 == "data-vw-visible";
         }
         return false;
      }

      private function isAllowedAttributeValue(param1:String, param2:CanvasHtmlAttribute) : Boolean
      {
         var name:String = param2.name;
         var value:String = param2.value;
         if(name == "id" || name == "data-vw-text" || name == "data-vw-visible" || name == "items" || name == "when" || name == "value")
         {
            return this.isIdentifier(value);
         }
         if(name == "class")
         {
            return this.isIdentifierList(value);
         }
         if(name == "template")
         {
            return value.length > 1 && value.charAt(0) == "#" && this.isIdentifier(value.substr(1));
         }
         if(param1 == "meta" && name == "charset")
         {
            return value == "utf-8";
         }
         if(param1 == "link" && name == "rel")
         {
            return value == "stylesheet";
         }
         if(name == "src" || name == "href")
         {
            return value.length > 0;
         }
         if(name == "viewbox")
         {
            return this.isFourFiniteNumbers(value);
         }
         if(name == "width" || name == "height" || name == "stroke-width")
         {
            return name == "stroke-width" ? this.isFiniteNumber(value,true) : this.isLength(value,true);
         }
         if(name == "x" || name == "y")
         {
            return this.isLength(value,false);
         }
         if(name == "fill" || name == "stroke")
         {
            return this.isPaint(value);
         }
         if(name == "clip-rule" || name == "fill-rule")
         {
            return value == "nonzero" || value == "evenodd";
         }
         if(name == "preserveaspectratio")
         {
            return value == "none" || value == "xmidymid meet" || value == "xmidymid slice";
         }
         if(name == "stroke-linecap")
         {
            return value == "butt" || value == "round" || value == "square";
         }
         if(name == "stroke-linejoin")
         {
            return value == "miter" || value == "round" || value == "bevel";
         }
         if(name == "vector-effect")
         {
            return value == "none" || value == "non-scaling-stroke";
         }
         if(name == "d")
         {
            return value.length > 0;
         }
         return value.length <= CanvasHtmlLimits.MAX_STRING_CODE_UNITS;
      }

      private function recordIdentityAndReferences(param1:CanvasHtmlNode) : void
      {
         var referenceOffset:int = -1;
         var identifier:String = param1.getAttribute("id");
         if(identifier != null)
         {
            if(this.identities.hasOwnProperty(identifier))
            {
               this.reject("duplicate-identity",param1.getAttributeOffset("id"),null,"compose");
               return;
            }
            this.identities[identifier] = true;
         }
         if(param1.name == "link")
         {
            referenceOffset = CanvasUtf8Decoder.byteOffset(this.source,param1.getAttributeValueOffset("href"));
            param1.referenceOffset = referenceOffset;
            this.document.references.push(new CanvasHtmlReference(CanvasHtmlReference.STYLESHEET,param1.getAttribute("href"),referenceOffset));
         }
         else if(param1.name == "img")
         {
            referenceOffset = CanvasUtf8Decoder.byteOffset(this.source,param1.getAttributeValueOffset("src"));
            param1.referenceOffset = referenceOffset;
            this.document.references.push(new CanvasHtmlReference(CanvasHtmlReference.IMAGE,param1.getAttribute("src"),referenceOffset));
         }
         else if(param1.name == "vw-include")
         {
            referenceOffset = CanvasUtf8Decoder.byteOffset(this.source,param1.getAttributeValueOffset("src"));
            param1.referenceOffset = referenceOffset;
            this.document.references.push(new CanvasHtmlReference(CanvasHtmlReference.INCLUDE,param1.getAttribute("src"),referenceOffset));
         }
         else if(param1.name == "style")
         {
            this.document.inlineStyleCount++;
         }
      }

      private function validateClosedElement(param1:CanvasHtmlNode, param2:int) : Boolean
      {
         var child:CanvasHtmlNode = null;
         if(param1.getAttribute("data-vw-text") != null && param1.children.length != 0)
         {
            this.reject("invalid-value",param1.offset);
            return false;
         }
         if(this.isEmptyElement(param1.name) && param1.children.length != 0)
         {
            this.reject("malformed-syntax",param2);
            return false;
         }
         if(param1.name == "html")
         {
            if(param1.children.length != 2 || CanvasHtmlNode(param1.children[0]).name != "head" || CanvasHtmlNode(param1.children[1]).name != "body")
            {
               this.reject("malformed-syntax",param2);
               return false;
            }
         }
         else if(param1.name == "head")
         {
            if(param1.children.length == 0 || CanvasHtmlNode(param1.children[0]).name != "title")
            {
               this.reject("malformed-syntax",param2);
               return false;
            }
            for each(child in param1.children)
            {
               if(child !== param1.children[0] && child.name != "meta" && child.name != "link" && child.name != "style")
               {
                  this.reject("malformed-syntax",child.offset);
                  return false;
               }
            }
         }
         else if(param1.name == "title" || param1.name == "style")
         {
            if(param1.children.length > 1 || param1.children.length == 1 && CanvasHtmlNode(param1.children[0]).type != CanvasHtmlNode.TEXT)
            {
               this.reject("malformed-syntax",param2);
               return false;
            }
         }
         else if(param1.name == "ul" || param1.name == "ol")
         {
            for each(child in param1.children)
            {
               if(child.name != "li")
               {
                  this.reject("malformed-syntax",child.offset);
                  return false;
               }
            }
         }
         return true;
      }

      private function allowsChild(param1:CanvasHtmlNode, param2:String) : Boolean
      {
         if(param1.name == "html")
         {
            if(param1.children.length == 0)
            {
               return param2 == "head";
            }
            return param1.children.length == 1 && param2 == "body";
         }
         if(param1.name == "head")
         {
            return param1.children.length == 0 ? param2 == "title" : param2 == "meta" || param2 == "link" || param2 == "style";
         }
         if(param1.name == "ul" || param1.name == "ol")
         {
            return param2 == "li";
         }
         if(param1.name == "svg")
         {
            return param2 == "svg" || param2 == "path";
         }
         if(this.isFlowContainer(param1.name))
         {
            return this.isFlowElement(param2);
         }
         return false;
      }

      private function allowsText(param1:String) : Boolean
      {
         return param1 == "title" || param1 == "style" || this.isFlowContainer(param1);
      }

      private function isKnownElement(param1:String) : Boolean
      {
         return param1 == "html" || param1 == "head" || param1 == "title" || param1 == "meta" || param1 == "link" || param1 == "style" || param1 == "body" || this.isFlowElement(param1) || param1 == "li" || param1 == "path";
      }

      private function isFlowElement(param1:String) : Boolean
      {
         return param1 == "main" || param1 == "header" || param1 == "footer" || param1 == "section" || param1 == "div" || param1 == "span" || param1 == "h1" || param1 == "h2" || param1 == "h3" || param1 == "h4" || param1 == "h5" || param1 == "h6" || param1 == "p" || param1 == "br" || param1 == "hr" || param1 == "ul" || param1 == "ol" || param1 == "button" || param1 == "template" || param1 == "img" || param1 == "svg" || param1 == "vw-include" || param1 == "vw-use" || param1 == "vw-repeat" || param1 == "vw-state" || param1 == "vw-meter";
      }

      private function isFlowContainer(param1:String) : Boolean
      {
         return param1 == "body" || param1 == "main" || param1 == "header" || param1 == "footer" || param1 == "section" || param1 == "div" || param1 == "span" || param1 == "h1" || param1 == "h2" || param1 == "h3" || param1 == "h4" || param1 == "h5" || param1 == "h6" || param1 == "p" || param1 == "li" || param1 == "button" || param1 == "template" || param1 == "vw-repeat" || param1 == "vw-state";
      }

      private function isGlobalElement(param1:String) : Boolean
      {
         return param1 == "body" || param1 == "main" || param1 == "header" || param1 == "footer" || param1 == "section" || param1 == "div" || param1 == "span" || param1 == "h1" || param1 == "h2" || param1 == "h3" || param1 == "h4" || param1 == "h5" || param1 == "h6" || param1 == "p" || param1 == "br" || param1 == "hr" || param1 == "ul" || param1 == "ol" || param1 == "li" || param1 == "button";
      }

      private function isGlobalAttribute(param1:String) : Boolean
      {
         return param1 == "id" || param1 == "class" || param1 == "data-vw-text" || param1 == "data-vw-visible";
      }

      private function isEmptyElement(param1:String) : Boolean
      {
         return param1 == "meta" || param1 == "link" || param1 == "br" || param1 == "hr" || param1 == "img" || param1 == "path" || param1 == "vw-include" || param1 == "vw-use" || param1 == "vw-meter";
      }

      private function tokenHasAttribute(param1:CanvasHtmlToken, param2:String) : Boolean
      {
         var attribute:CanvasHtmlAttribute = null;
         for each(attribute in param1.attributes)
         {
            if(attribute.name == param2)
            {
               return true;
            }
         }
         return false;
      }

      private function isIdentifier(param1:String) : Boolean
      {
         if(param1 == null || param1.length == 0 || param1.length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH || !this.isLowerLetter(param1.charCodeAt(0)))
         {
            return false;
         }
         var code:int = 0;
         for(var index:int = 1; index < param1.length; index++)
         {
            code = param1.charCodeAt(index);
            if(!(this.isLowerLetter(code) || code >= 48 && code <= 57 || code == 45))
            {
               return false;
            }
         }
         return true;
      }

      private function isIdentifierList(param1:String) : Boolean
      {
         if(param1 == null || param1.length == 0 || param1.charAt(0) == " " || param1.charAt(param1.length - 1) == " " || param1.indexOf("  ") >= 0)
         {
            return false;
         }
         var item:String = null;
         for each(item in param1.split(" "))
         {
            if(!this.isIdentifier(item))
            {
               return false;
            }
         }
         return true;
      }

      private function exceedsIdentifierLimit(param1:String, param2:String) : Boolean
      {
         if(param1 == "id" || param1 == "data-vw-text" || param1 == "data-vw-visible" || param1 == "items" || param1 == "when" || param1 == "value")
         {
            return param2.length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH;
         }
         if(param1 == "template")
         {
            return param2.length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH + 1;
         }
         if(param1 == "class")
         {
            var item:String = null;
            for each(item in param2.split(" "))
            {
               if(item.length > CanvasHtmlLimits.MAX_IDENTIFIER_LENGTH)
               {
                  return true;
               }
            }
         }
         return false;
      }

      private function isFourFiniteNumbers(param1:String) : Boolean
      {
         if(param1 == null || param1.length == 0 || param1.charAt(0) == " " || param1.charAt(param1.length - 1) == " " || param1.indexOf("  ") >= 0)
         {
            return false;
         }
         var values:Array = param1.split(" ");
         if(values.length != 4)
         {
            return false;
         }
         var value:String = null;
         for each(value in values)
         {
            if(!this.isFiniteNumber(value,false))
            {
               return false;
            }
         }
         return true;
      }

      private function isFiniteNumber(param1:String, param2:Boolean) : Boolean
      {
         if(param1 == null || param1.length == 0)
         {
            return false;
         }
         var index:int = 0;
         if(param1.charAt(0) == "-")
         {
            if(param2 || param1.length == 1)
            {
               return false;
            }
            index++;
         }
         var integerStart:int = index;
         while(index < param1.length && param1.charCodeAt(index) >= 48 && param1.charCodeAt(index) <= 57)
         {
            index++;
         }
         if(index == integerStart || index - integerStart > 1 && param1.charAt(integerStart) == "0")
         {
            return false;
         }
         if(index < param1.length && param1.charAt(index) == ".")
         {
            index++;
            var fractionStart:int = index;
            while(index < param1.length && param1.charCodeAt(index) >= 48 && param1.charCodeAt(index) <= 57)
            {
               index++;
            }
            if(index == fractionStart)
            {
               return false;
            }
         }
         if(index != param1.length)
         {
            return false;
         }
         var value:Number = Number(param1);
         return isFinite(value) && (!param2 || value >= 0);
      }

      private function isLength(param1:String, param2:Boolean) : Boolean
      {
         if(param1 == "0")
         {
            return true;
         }
         if(param1 == null || param1.length <= 2 || param1.substr(param1.length - 2) != "px")
         {
            return false;
         }
         return this.isFiniteNumber(param1.substring(0,param1.length - 2),param2);
      }

      private function isPaint(param1:String) : Boolean
      {
         if(param1 == "none" || param1 == "currentcolor" || param1 == "transparent")
         {
            return true;
         }
         if(param1 == null || param1.charAt(0) != "#" || param1.length != 7 && param1.length != 9)
         {
            return false;
         }
         var code:int = 0;
         for(var index:int = 1; index < param1.length; index++)
         {
            code = param1.charCodeAt(index);
            if(!(code >= 48 && code <= 57 || code >= 97 && code <= 102))
            {
               return false;
            }
         }
         return true;
      }

      private function isOnlyWhitespace(param1:String) : Boolean
      {
         var code:int = 0;
         for(var index:int = 0; index < param1.length; index++)
         {
            code = param1.charCodeAt(index);
            if(code != 32 && code != 9 && code != 10 && code != 13)
            {
               return false;
            }
         }
         return true;
      }

      private function isLowerLetter(param1:int) : Boolean
      {
         return param1 >= 97 && param1 <= 122;
      }

      private function reject(param1:String, param2:int, param3:String = null, param4:String = "parse") : void
      {
         if(this.failure == null)
         {
            this.failure = new CanvasHtmlDiagnostic(param4,param1,this.resource,CanvasUtf8Decoder.byteOffset(this.source,param2),param3);
         }
      }

      private function makeDiagnostic(param1:String, param2:int) : CanvasHtmlDiagnostic
      {
         return new CanvasHtmlDiagnostic("parse",param1,this.resource,CanvasUtf8Decoder.byteOffset(this.source,param2));
      }
   }
}
